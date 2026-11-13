# Central de Demandas: envia uma conversa operacional ao HUB Finture como
# demanda. A demanda NASCE no primeiro momento em que a conversa está na etapa
# `em_atendimento` do Kanban E tem responsável — não importa qual dos dois
# aconteceu primeiro (o listener enfileira nos dois eventos; aqui o estado é
# relido do banco). Depois de criada, toda mudança relevante (responsável,
# etapa, status, time, plano de ação, resumo da IA) é reenviada como `updated`.
#
# O HUB faz UPSERT por `external_id` (chatwoot:<account_id>:<display_id>), então
# reenviar é sempre seguro. O estado do envio fica em finture_demanda_syncs,
# nunca em custom_attributes (o n8n regrava esse hash inteiro, e gravar nele
# dispararia o próprio listener desta integração).
class Finture::DemandaSyncService
  STAGE_KEY = Finture::StageChangeService::STAGE_KEY
  TARGET_STAGE = 'em_atendimento'.freeze
  # Chaves de custom_attributes cuja mudança interessa ao HUB.
  WATCHED_ATTRIBUTES = %w[sdr_stage sdr_next_action sdr_resumo_ia sdr_resumo produto_interesse].freeze
  PAYLOAD_VERSION = 1
  ORIGEM = 'chatwoot'.freeze
  # Campos que variam a cada envio e por isso ficam fora do hash de dedupe.
  VOLATILE_KEYS = %w[ocorrido_em evento].freeze

  pattr_initialize [:conversation!, :occurred_at!]

  def self.external_id(conversation)
    "#{ORIGEM}:#{conversation.account_id}:#{conversation.display_id}"
  end

  # Está em "Em atendimento" e tem responsável humano?
  def self.eligible?(conversation)
    stage = (conversation.custom_attributes || {})[STAGE_KEY].to_s
    stage == TARGET_STAGE && conversation.assignee_id.present?
  end

  # => :disabled | :skipped | :unchanged | :created | :updated | :failed
  def perform
    return :disabled unless Finture::HubClient.configured?
    return :skipped unless applicable?

    sync = conversation.finture_demanda_sync || create_sync!
    send_with_lock(sync)
  end

  # Payload do contrato (API_DEMANDAS.md no HUB, payload_version 1).
  def payload(evento)
    attrs = conversation.custom_attributes || {}
    {
      origem: ORIGEM,
      external_id: self.class.external_id(conversation),
      evento: evento,
      payload_version: PAYLOAD_VERSION,
      titulo: titulo(attrs)
    }.merge(content_fields(attrs), people_fields, origin_fields(attrs))
  end

  private

  # Caixa operacional e (já é demanda ou acabou de ficar elegível).
  def applicable?
    return false unless Finture::InboxConfig.operational?(conversation.inbox)

    conversation.finture_demanda_sync.present? || self.class.eligible?(conversation)
  end

  # Serializa jobs concorrentes da mesma conversa (eventos chegam em rajada).
  # O erro passageiro é registrado FORA do with_lock: dentro dele a exceção
  # desfaria a própria gravação de `retrying` (rollback da transação).
  def send_with_lock(sync)
    transient = nil
    result = sync.with_lock do
      conversation.reload
      begin
        send!(sync)
      rescue Finture::HubClient::TransientError => e
        transient = e
        :retrying
      end
    end
    return result unless transient

    record_attempt!(sync, status: 'retrying', error: transient)
    raise transient
  end

  def create_sync!
    Finture::DemandaSync.create!(
      account_id: conversation.account_id,
      conversation: conversation,
      inbox_id: conversation.inbox_id,
      external_id: self.class.external_id(conversation)
    )
  rescue ActiveRecord::RecordNotUnique
    conversation.reload.finture_demanda_sync
  end

  def send!(sync)
    evento = sync.hub_demanda_id.present? ? 'updated' : 'created'
    body = payload(evento)
    digest = payload_hash(body)
    return :unchanged if sync.synced? && sync.last_payload_hash == digest

    response = Finture::HubClient.new.upsert_demanda(body)
    record_success!(sync, evento, digest, response)
    evento == 'created' ? :created : :updated
  rescue Finture::HubClient::Error => e
    raise if e.is_a?(Finture::HubClient::TransientError)

    record_attempt!(sync, status: 'failed', error: e)
    Rails.logger.error("[finture-demanda] HUB recusou a demanda #{sync.external_id}: #{e.message}")
    :failed
  end

  def record_success!(sync, evento, digest, response)
    sync.update!(
      hub_demanda_id: response.dig('demanda', 'id').presence || sync.hub_demanda_id,
      status: 'synced', last_event: evento, last_payload_hash: digest,
      last_sent_at: Time.current, last_error: nil, attempts: sync.attempts + 1
    )
  end

  def record_attempt!(sync, status:, error:)
    sync.update!(status: status, last_error: error.message.truncate(1000), attempts: sync.attempts + 1)
  end

  def payload_hash(body)
    stable = body.to_h.reject { |key, _| VOLATILE_KEYS.include?(key.to_s) }
    Digest::SHA256.hexdigest(stable.to_json)
  end

  def content_fields(attrs)
    {
      contexto: attrs['sdr_resumo_ia'].presence,
      plano_acao: attrs['sdr_next_action'].presence,
      resumo_final: attrs['sdr_resumo'].presence,
      produto_interesse: attrs['produto_interesse'].presence
    }
  end

  def people_fields
    assignee = conversation.assignee
    contact = conversation.contact
    {
      responsavel_email: assignee&.email&.downcase.presence,
      responsavel_nome: assignee&.name.presence,
      time: conversation.team&.name.presence,
      contato: { nome: contact&.name.presence, telefone: contact&.phone_number.presence, email: contact&.email.presence }
    }
  end

  def origin_fields(attrs)
    inbox = conversation.inbox
    {
      canal: inbox.channel_type.to_s.delete_prefix('Channel::'),
      caixa: { id: inbox.id, nome: inbox.name },
      etapa: attrs[STAGE_KEY].presence || Finture::PipelineStage::DEFAULT_SLUG,
      status_origem: conversation.status.to_s,
      link: link,
      ocorrido_em: occurred_at.utc.iso8601
    }
  end

  def titulo(attrs)
    contact = conversation.contact
    quem = contact&.name.presence || contact&.phone_number.presence || "Conversa ##{conversation.display_id}"
    assunto = attrs['produto_interesse'].presence || conversation.inbox.name
    "#{quem} — #{assunto}"
  end

  def link
    "#{ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')}/app/accounts/#{conversation.account_id}/conversations/#{conversation.display_id}"
  end
end
