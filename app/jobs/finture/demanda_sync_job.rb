# Envia (ou reenvia) uma conversa ao HUB como demanda (Finture::DemandaSyncService).
# Enfileirado pelo Finture::DemandaListener (horário do evento + autor) e pela
# reconciliação (Finture::DemandaReconcileService: horário do reenvio, sem
# autor). O service relê o estado atual da conversa, então eventos atrasados ou
# repetidos não fazem mal. Erro passageiro do HUB tenta de novo com espera
# crescente, com os MESMOS argumentos: o corpo sai igual (mesma sequência) e o
# HUB deduplica. Esgotadas as tentativas, a linha fica "failed".
#
#   occurred_at  ISO-8601 do evento; sem ele, vale o horário da execução
#                (reprocessamento manual pelo console)
#   actor_id     User que fez a mudança pelo painel; nil = sem autor
#   force        envia mesmo que o conteúdo seja igual ao último aplicado
class Finture::DemandaSyncJob < ApplicationJob
  queue_as :low

  retry_on Finture::HubClient::TransientError, wait: :polynomially_longer, attempts: 6 do |job, error|
    sync = Finture::DemandaSync.find_by(conversation_id: job.arguments.first)
    sync&.mark_failed!("tentativas esgotadas: #{error.message}")
  end
  discard_on ActiveRecord::RecordNotFound

  def perform(conversation_id, occurred_at = nil, actor_id = nil, force = false) # rubocop:disable Style/OptionalBooleanParameter
    conversation = Conversation.find(conversation_id)
    at = occurred_at.present? ? Time.zone.parse(occurred_at.to_s) : nil
    actor = actor_id.present? ? User.find_by(id: actor_id) : nil
    Finture::DemandaSyncService.new(conversation: conversation, occurred_at: at || Time.current, actor: actor, force: force).perform
  end
end
