# Envia UMA mensagem agendada. Sem retry automático: o claim atômico dentro do
# service já impede duplicidade, e qualquer falha fica registrada no próprio
# agendamento (status failed + aviso ao autor).
class Finture::SendScheduledMessageJob < ApplicationJob
  queue_as :high

  def perform(scheduled_message_id)
    item = Finture::ScheduledMessage.find_by(id: scheduled_message_id)
    return if item.blank?

    Finture::ScheduledMessageService.new(scheduled_message: item).deliver!
  end
end
