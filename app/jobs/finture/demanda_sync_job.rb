# Envia (ou reenvia) uma conversa ao HUB como demanda (Finture::DemandaSyncService).
# Enfileirado pelo Finture::DemandaListener; o service relê o estado atual da
# conversa, então eventos atrasados ou repetidos não fazem mal. Erro passageiro
# do HUB tenta de novo com espera crescente; esgotadas as tentativas, a linha de
# sync fica "failed" com o último erro para diagnóstico.
class Finture::DemandaSyncJob < ApplicationJob
  queue_as :low

  retry_on Finture::HubClient::TransientError, wait: :polynomially_longer, attempts: 6 do |job, error|
    sync = Finture::DemandaSync.find_by(conversation_id: job.arguments.first)
    sync&.update!(status: 'failed', last_error: "tentativas esgotadas: #{error.message}".truncate(1000))
  end
  discard_on ActiveRecord::RecordNotFound

  def perform(conversation_id, occurred_at = nil)
    conversation = Conversation.find(conversation_id)
    at = occurred_at.present? ? Time.zone.parse(occurred_at.to_s) : nil
    Finture::DemandaSyncService.new(conversation: conversation, occurred_at: at || Time.current).perform
  end
end
