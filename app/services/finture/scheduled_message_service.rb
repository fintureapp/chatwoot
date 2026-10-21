# Ciclo de vida da mensagem agendada: agendar, editar, cancelar e ENVIAR.
# Toda transição deixa rastro na conversa (mensagem de atividade); falha e
# cancelamento automático também avisam o autor por nota privada com menção
# (vira notificação no sino via Messages::MentionService).
class Finture::ScheduledMessageService
  pattr_initialize [:scheduled_message!]

  delegate :conversation, :account, :user, to: :scheduled_message

  def schedule!
    scheduled_message.save!
    activity(:scheduled, user_name: author_name, time: formatted_time)
    scheduled_message
  end

  def update!(attrs)
    raise CustomExceptions::Finture::ScheduledMessageNotPending.new({}) unless scheduled_message.pending?

    scheduled_message.update!(attrs)
    activity(:updated, user_name: Current.user&.available_name || author_name, time: formatted_time)
    scheduled_message
  end

  def cancel!
    raise CustomExceptions::Finture::ScheduledMessageNotPending.new({}) unless scheduled_message.pending?

    scheduled_message.update!(status: 'cancelled', cancel_reason: 'user')
    activity(:cancelled, user_name: Current.user&.available_name || author_name, time: formatted_time)
    scheduled_message
  end

  # Chamado pelo job no horário. Idempotente: só prossegue se vencer o claim.
  def deliver!
    return unless scheduled_message.claim!

    scheduled_message.reload
    return auto_cancel! if should_auto_cancel?
    return fail!(I18n.t('finture.scheduled_messages.errors.window_closed')) unless conversation.can_reply?

    send_message!
  rescue StandardError => e
    Rails.logger.error("[Finture::ScheduledMessage##{scheduled_message.id}] #{e.class}: #{e.message}")
    fail!(e.message)
  end

  # Registro em `processing` há tempo demais: o worker caiu antes de concluir.
  # Como mensagem + status mudam na mesma transação, nada foi enviado.
  def expire_stale!
    fail!(I18n.t('finture.scheduled_messages.errors.interrupted'))
  end

  private

  def should_auto_cancel?
    scheduled_message.cancel_on_reply &&
      conversation.messages.incoming.exists?(['created_at > ?', scheduled_message.created_at])
  end

  def auto_cancel!
    scheduled_message.update!(status: 'cancelled', cancel_reason: 'client_replied')
    activity(:auto_cancelled, time: formatted_time)
    notify_author(I18n.t('finture.scheduled_messages.notes.auto_cancelled', time: formatted_time, preview: preview))
  end

  def send_message!
    message = nil
    ActiveRecord::Base.transaction do
      message = Messages::MessageBuilder.new(
        user, conversation,
        { content: scheduled_message.content, private: false,
          content_attributes: { finture_scheduled_message_id: scheduled_message.id } }
      ).perform
      scheduled_message.update!(status: 'sent', sent_at: Time.current, message: message)
    end
    activity(:sent, user_name: author_name, time: formatted_time)
    message
  end

  def fail!(reason)
    scheduled_message.update!(status: 'failed', error_message: reason.to_s.truncate(1000))
    activity(:failed, time: formatted_time, reason: reason)
    notify_author(I18n.t('finture.scheduled_messages.notes.failed', time: formatted_time, reason: reason, preview: preview))
  end

  # Nota privada mencionando o autor → notificação de menção para ele.
  def notify_author(text)
    return if user.blank?

    mention = "[@#{user.available_name}](mention://user/#{user.id}/#{ERB::Util.url_encode(user.available_name)})"
    conversation.messages.create!(
      account_id: account.id, inbox_id: conversation.inbox_id, message_type: :outgoing,
      private: true, content: "#{mention} #{text}"
    )
  end

  def activity(key, **args)
    content = I18n.t("finture.scheduled_messages.activity.#{key}", **args)
    Conversations::ActivityMessageJob.perform_later(
      conversation,
      { account_id: account.id, inbox_id: conversation.inbox_id, message_type: :activity, content: content }
    )
  end

  def author_name
    user&.available_name || I18n.t('finture.scheduled_messages.unknown_author')
  end

  def formatted_time
    scheduled_message.scheduled_at.in_time_zone(Finture::ScheduledMessage::TIMEZONE).strftime('%d/%m/%Y %H:%M')
  end

  def preview
    scheduled_message.content.to_s.truncate(80)
  end
end
