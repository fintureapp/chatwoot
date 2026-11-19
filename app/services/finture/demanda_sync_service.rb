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
#
# Payload v2 (padrão): o v1 + conversa_criada_em, elegivel_em (só quando
# registrado), sequencia e autor (só quando um usuário fez a mudança pelo
# painel). FINTURE_HUB_PAYLOAD_VERSION=1 volta a enviar o v1 exato.
#
# Resposta: só um envio APLICADO (motivo null ou "duplicado") deixa a linha
# `synced` e grava o hash. `ignorado: true` (futuro, atrasado) deixa
# `divergent` com recuperação pendente, sem hash, para o próximo envio sair.
class Finture::DemandaSyncService
  STAGE_KEY = Finture::StageChangeService::STAGE_KEY
  TARGET_STAGE = 'em_atendimento'.freeze
  # Chaves de custom_attributes cuja mudança interessa ao HUB.
  WATCHED_ATTRIBUTES = %w[sdr_stage sdr_next_action sdr_resumo_ia sdr_resumo produto_interesse].freeze
  PAYLOAD_VERSION = 2
  ORIGEM = 'chatwoot'.freeze
  # Fora do hash de conteúdo: o que muda a cada envio (ocorrido_em, evento,
  # sequencia, autor) e os metadados do v2 que não mudam a demanda.
  NON_CONTENT_KEYS = %i[ocorrido_em evento conversa_criada_em elegivel_em sequencia autor].freeze
  # O hash de conteúdo é sempre calculado no formato do v1 (payload_version 1):
  # a troca de versão não faz conversa nenhuma parecer alterada, nos dois sentidos.
  CONTENT_HASH_VERSION = 1
  AUTHOR_FIELD_LIMIT = 200

  # actor: User que fez a mudança pelo painel (nil = automação, API ou sistema).
  # force: envia mesmo que o conteúdo seja igual ao último aplicado.
  pattr_initialize [:conversation!, :occurred_at!, :actor, :force]

  def self.external_id(conversation)
    "#{ORIGEM}:#{conversation.account_id}:#{conversation.display_id}"
  end

  # Está em "Em atendimento" e tem responsável humano?
  def self.eligible?(conversation)
    stage = (conversation.custom_attributes || {})[STAGE_KEY].to_s
    stage == TARGET_STAGE && conversation.assignee_id.present?
  end

  # 2, ou 1 com FINTURE_HUB_PAYLOAD_VERSION=1 (HUB que ainda não aceita o v2).
  def self.payload_version
    ENV.fetch('FINTURE_HUB_PAYLOAD_VERSION', '').to_s.strip == '1' ? 1 : PAYLOAD_VERSION
  end

  # => :disabled | :skipped | :unchanged | :created | :updated | :divergent | :failed
  def perform
    return :disabled unless Finture::HubClient.configured?
    return :skipped unless applicable?

    sync = conversation.finture_demanda_sync || create_sync!
    send_with_lock(sync)
  end

  # Payload do contrato (API_DEMANDAS.md no HUB). Sem `sequencia`, que só é
  # atribuída no envio (#with_sequencia).
  def payload(evento, sync = conversation.finture_demanda_sync)
    attrs = conversation.custom_attributes || {}
    body = {
      origem: ORIGEM,
      external_id: self.class.external_id(conversation),
      evento: evento,
      payload_version: self.class.payload_version,
      titulo: titulo(attrs)
    }.merge(content_fields(attrs), people_fields, origin_fields(attrs))
    body[:payload_version] == 1 ? body : body.merge(v2_fields(sync))
  end

  # O estado atual da conversa difere do último aplicado no HUB? (reconciliação)
  def content_changed?(sync)
    applicable? && content_hash(payload('updated', sync)) != sync.last_payload_hash
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

    sync.update!(status: 'retrying', last_error: transient.message.truncate(1000), attempts: sync.attempts + 1)
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
    body = payload(evento, sync)
    digest = content_hash(body)
    return :unchanged if !force && sync.synced? && sync.last_payload_hash == digest

    response = Finture::HubClient.new.upsert_demanda(with_sequencia(body, sync))
    record_response!(sync, evento, digest, response)
  rescue Finture::HubClient::Error => e
    raise if e.is_a?(Finture::HubClient::TransientError)

    sync.attempts += 1
    sync.mark_failed!(e.message)
    Rails.logger.error("[finture-demanda] HUB recusou a demanda #{sync.external_id}: #{e.message}")
    :failed
  end

  # A retentativa do MESMO envio (corpo idêntico) reaproveita o número e sai
  # igual byte a byte, então o HUB a reconhece como duplicada. Qualquer outro
  # envio ganha o número seguinte, inclusive dois no mesmo segundo.
  def with_sequencia(body, sync)
    return body if body[:payload_version] == 1

    attempt = Digest::SHA256.hexdigest(body.to_json)
    sequencia = sync.attempt_hash == attempt ? sync.sequencia : sync.sequencia + 1
    sync.update!(sequencia: sequencia, attempt_hash: attempt)
    body.merge(sequencia: sequencia)
  end

  def record_response!(sync, evento, digest, response)
    hub_id = response.dig('demanda', 'id').presence || sync.hub_demanda_id
    return record_rejection!(sync, hub_id, response['motivo'].presence || 'ignorado') if response['ignorado'] == true

    sync.update!(
      hub_demanda_id: hub_id, status: 'synced', last_event: evento, last_payload_hash: digest,
      hub_motivo: response['motivo'].presence, last_sent_at: Time.current, last_error: nil, attempts: sync.attempts + 1,
      **recovered_attributes(sync)
    )
    evento == 'created' ? :created : :updated
  end

  # HUB recebeu e não aplicou (futuro, atrasado). Não é sucesso: sem hash, para
  # o próximo envio (ou a reconciliação) sair mesmo com o conteúdo igual.
  def record_rejection!(sync, hub_id, motivo)
    sync.update!(hub_demanda_id: hub_id, status: 'divergent', hub_motivo: motivo, recovery_state: 'pending',
                 rejected_at: Time.current, last_error: "HUB não aplicou o evento (motivo: #{motivo})",
                 attempts: sync.attempts + 1)
    Rails.logger.warn("[finture-demanda] HUB não aplicou #{sync.external_id} (motivo: #{motivo}, sequencia: #{sync.sequencia})")
    :divergent
  end

  def recovered_attributes(sync)
    return {} unless Finture::DemandaSync::OPEN_RECOVERY.include?(sync.recovery_state)

    { recovery_state: 'recovered', recovered_at: Time.current }
  end

  # Hash do CONTEÚDO, no formato do v1 (mesmas chaves, mesma ordem).
  def content_hash(body)
    content = body.except(*NON_CONTENT_KEYS).merge(payload_version: CONTENT_HASH_VERSION)
    Digest::SHA256.hexdigest(content.to_json)
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

  # elegivel_em só quando registrado (nunca aproximado); autor só com usuário.
  def v2_fields(sync)
    fields = { conversa_criada_em: conversation.created_at.utc.iso8601 }
    fields[:elegivel_em] = sync.elegivel_em.utc.iso8601 if sync&.elegivel_em.present?
    author = autor
    fields[:autor] = author if author
    fields
  end

  def autor
    return unless actor.is_a?(User) && actor.email.present?

    { email: actor.email.strip.downcase.first(AUTHOR_FIELD_LIMIT), nome: actor.name.to_s.strip.first(AUTHOR_FIELD_LIMIT).presence }
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
