# Roda a cada minuto (config/schedule.yml): enfileira um job por mensagem
# agendada vencida e encerra registros travados em `processing`.
class Finture::ScheduledMessagesDispatcherJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Finture::ScheduledMessage.due.find_each do |item|
      Finture::SendScheduledMessageJob.perform_later(item.id)
    end

    Finture::ScheduledMessage.stale_processing.find_each do |item|
      Finture::ScheduledMessageService.new(scheduled_message: item).expire_stale!
    end
  end
end
