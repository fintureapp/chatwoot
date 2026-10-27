# Transcreve um áudio recebido (Finture::AudioTranscriptionService). Enfileirado
# na criação do anexo; o service decide se a caixa transcreve. Erro passageiro
# (rede, 429, 5xx, arquivo ainda subindo) tenta de novo; esgotadas as
# tentativas, o anexo fica "failed" e o n8n pede ao cliente para repetir.
class Finture::AudioTranscriptionJob < ApplicationJob
  queue_as :medium

  retry_on Finture::TranscriptionClient::TransientError, ActiveStorage::FileNotFoundError,
           wait: :polynomially_longer, attempts: 3 do |job, error|
    attachment = Attachment.find_by(id: job.arguments.first)
    Finture::AudioTranscriptionService.new(attachment).mark_failed!(error) if attachment
  end

  def perform(attachment_id)
    attachment = Attachment.find_by(id: attachment_id)
    return if attachment.blank?

    Finture::AudioTranscriptionService.new(attachment).perform
  end
end
