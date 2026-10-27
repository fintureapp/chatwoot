class CustomExceptions::Finture::ScheduledMessageNotPending < CustomExceptions::Base
  def message
    I18n.t('finture.scheduled_messages.errors.not_pending')
  end
end
