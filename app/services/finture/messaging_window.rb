# Instante em que a janela de resposta do canal fecha (nil = canal sem janela).
# Espelha Conversations::MessageWindowService, que só responde "pode ou não"
# para AGORA; aqui precisamos do horário para validar um agendamento futuro.
module Finture::MessagingWindow
  def self.closes_at(conversation)
    window = duration_for(conversation)
    return nil if window.blank?

    last_incoming = conversation.messages.where(account_id: conversation.account_id).incoming.last
    return Time.at(0).utc if last_incoming.blank?

    last_incoming.created_at + window
  end

  def self.duration_for(conversation)
    Conversations::MessageWindowService.new(conversation).send(:messaging_window)
  end
end
