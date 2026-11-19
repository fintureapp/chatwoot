# Central de Demandas: decide se uma mudança na conversa interessa ao HUB e
# enfileira o envio (Finture::DemandaSyncJob). Quem relê o estado e decide
# criar/atualizar é o Finture::DemandaSyncService.
#
# Dispara em: responsável (assignee_id), status, time (team_id) e
# custom_attributes quando alguma chave vigiada mudou (etapa, plano de ação,
# resumo da IA, resumo final, produto). Ignora etiqueta, prioridade, soneca,
# etc. — e a regravação do hash de custom_attributes pelo n8n sem mudança real.
#
# Roda SÍNCRONO (SyncDispatcher), logo depois do commit da mudança, porque é o
# único ponto que ainda enxerga:
#   - quem fez a mudança (Current), que vira o `autor` do evento: só um usuário
#     do painel; automação (Current.executed_by), token de API e sistema → nil;
#   - o estado antes/depois desta mudança, para registrar `elegivel_em` no
#     instante exato em que a conversa ficou elegível (linha criada com ele).
# O trabalho pesado (HTTP) continua no job. Com as ENVs do HUB vazias, sai cedo:
# integração desligada.
class Finture::DemandaListener < BaseListener
  SIMPLE_KEYS = %w[assignee_id status team_id].freeze

  def conversation_updated(event)
    conversation = event.data[:conversation]
    changes = event.data[:changed_attributes] || {}
    return unless should_sync?(conversation, changes)

    record_eligibility(conversation, changes, event.timestamp)
    Finture::DemandaSyncJob.perform_later(*job_arguments(conversation, event.timestamp))
  rescue StandardError => e
    # Os listeners rodam em sequência no mesmo despacho: uma exceção aqui
    # impediria os seguintes. A demanda é acessória; só registra.
    Rails.logger.error("[Finture::DemandaListener] conversa #{conversation&.id}: #{e.class}: #{e.message}")
    ChatwootExceptionTracker.new(e, account: conversation&.account).capture_exception
  end

  private

  # Ordem pensada para o custo: ENV e diff são baratos; a consulta da caixa vem por último.
  def should_sync?(conversation, changes)
    return false if conversation.blank? || changes.blank? || !Finture::HubClient.configured?

    relevant?(changes) && Finture::InboxConfig.operational?(conversation.inbox)
  end

  def relevant?(changes)
    keys = changes.keys.map(&:to_s)
    return true if keys.intersect?(SIMPLE_KEYS)

    watched_attribute_changed?(changes['custom_attributes'] || changes[:custom_attributes])
  end

  def watched_attribute_changed?(diff)
    return false unless diff.is_a?(Array) && diff.size == 2

    before = diff[0].is_a?(Hash) ? diff[0] : {}
    after = diff[1].is_a?(Hash) ? diff[1] : {}
    Finture::DemandaSyncService::WATCHED_ATTRIBUTES.any? do |key|
      before[key] != after[key]
    end
  end

  # A conversa era inelegível antes desta mudança e é elegível agora: este é o
  # instante em que ela virou demanda. Falha aqui não impede o envio (o evento
  # só sai sem `elegivel_em`).
  def record_eligibility(conversation, changes, timestamp)
    return unless Finture::DemandaSyncService.eligible?(conversation)
    return if eligible_before?(conversation, changes)

    Finture::DemandaSync.open_for_eligibility!(conversation, timestamp || Time.current)
  rescue StandardError => e
    Rails.logger.error("[Finture::DemandaListener] elegivel_em da conversa #{conversation.id}: #{e.class}: #{e.message}")
  end

  def eligible_before?(conversation, changes)
    attrs = previous_value(changes, 'custom_attributes') { conversation.custom_attributes }
    stage = (attrs.is_a?(Hash) ? attrs : {})[Finture::DemandaSyncService::STAGE_KEY]
    assignee_id = previous_value(changes, 'assignee_id') { conversation.assignee_id }
    stage.to_s == Finture::DemandaSyncService::TARGET_STAGE && assignee_id.present?
  end

  # Valor antes desta mudança: o lado esquerdo do diff, ou o atual se não mudou.
  def previous_value(changes, key)
    diff = changes[key] || changes[key.to_sym]
    diff.is_a?(Array) && diff.size == 2 ? diff[0] : yield
  end

  # O autor só entra quando existe: sem ele, o job tem os mesmos 2 argumentos do
  # v1, e a volta à imagem anterior não quebra o que estiver na fila.
  def job_arguments(conversation, timestamp)
    arguments = [conversation.id, timestamp&.iso8601]
    actor = actor_id
    actor ? arguments + [actor] : arguments
  end

  # Usuário do painel que fez a mudança. Nunca o responsável por dedução nem o
  # contato; automação, token de API e sistema ficam sem autor.
  def actor_id
    return if Current.executed_by.present? || Current.api_access_token_auth

    user = Current.user
    user.is_a?(User) ? user.id : nil
  end
end
