# Central de Demandas: decide se uma mudança na conversa interessa ao HUB e
# enfileira o envio (Finture::DemandaSyncJob). Só filtra; quem relê o estado e
# decide criar/atualizar é o Finture::DemandaSyncService.
#
# Dispara em: responsável (assignee_id), status, time (team_id) e
# custom_attributes quando alguma chave vigiada mudou (etapa, plano de ação,
# resumo da IA, resumo final, produto). Ignora etiqueta, prioridade, soneca,
# etc. — e a regravação do hash de custom_attributes pelo n8n sem mudança real.
#
# Roda assíncrono (AsyncDispatcher). Com as ENVs do HUB vazias, sai cedo:
# integração desligada.
class Finture::DemandaListener < BaseListener
  SIMPLE_KEYS = %w[assignee_id status team_id].freeze

  def conversation_updated(event)
    conversation = event.data[:conversation]
    changes = event.data[:changed_attributes] || {}
    return unless should_sync?(conversation, changes)

    Finture::DemandaSyncJob.perform_later(conversation.id, event.timestamp&.iso8601)
  rescue StandardError => e
    # Os listeners rodam em sequência no mesmo EventDispatcherJob: uma exceção aqui
    # impediria webhooks e notificações deste evento. A demanda é acessória; só registra.
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
end
