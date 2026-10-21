# Mensagens agendadas da conversa. Horário chega como hora de parede em
# America/Sao_Paulo ("2026-10-21T15:30") e volta em ISO 8601 (UTC) + a mesma
# hora local já formatada, para a UI não depender do fuso do navegador.
class Api::V1::Accounts::Conversations::FintureScheduledMessagesController < Api::V1::Accounts::Conversations::BaseController
  before_action :scheduled_message, only: [:update, :destroy]

  def index
    items = scoped.order(Arel.sql("CASE WHEN status = 'pending' THEN 0 ELSE 1 END"), scheduled_at: :desc).limit(50)
    render json: { payload: items.map { |item| serialize(item) }, meta: window_meta }
  end

  def create
    item = scoped.new(
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      user: Current.user,
      content: params.require(:content),
      scheduled_at: parse_time,
      cancel_on_reply: cancel_on_reply_param(true)
    )
    Finture::ScheduledMessageService.new(scheduled_message: item).schedule!
    render json: serialize(item).merge(meta: window_meta)
  rescue CustomExceptions::Base => e
    render_could_not_create_error(e.message)
  end

  def update
    attrs = {}
    attrs[:content] = params[:content] if params.key?(:content)
    attrs[:scheduled_at] = parse_time if params[:scheduled_at].present?
    attrs[:cancel_on_reply] = cancel_on_reply_param(@scheduled_message.cancel_on_reply) if params.key?(:cancel_on_reply)
    Finture::ScheduledMessageService.new(scheduled_message: @scheduled_message).update!(attrs)
    render json: serialize(@scheduled_message)
  rescue CustomExceptions::Base => e
    render_could_not_create_error(e.message)
  end

  # Cancelar mantém o registro (rastreabilidade); nunca apaga.
  def destroy
    Finture::ScheduledMessageService.new(scheduled_message: @scheduled_message).cancel!
    render json: serialize(@scheduled_message)
  rescue CustomExceptions::Base => e
    render_could_not_create_error(e.message)
  end

  private

  def scoped
    Finture::ScheduledMessage.where(conversation_id: @conversation.id).includes(:user)
  end

  def scheduled_message
    @scheduled_message = scoped.find(params[:id])
  end

  def parse_time
    time = Finture::ScheduledMessage.parse_local(params.require(:scheduled_at))
    raise ActionController::ParameterMissing, :scheduled_at if time.blank?

    time
  end

  def cancel_on_reply_param(default)
    return default unless params.key?(:cancel_on_reply)

    ActiveModel::Type::Boolean.new.cast(params[:cancel_on_reply])
  end

  # Quando a janela do canal fecha (WhatsApp 24h etc.), para a UI avisar que um
  # agendamento depois disso só sai se o cliente responder antes.
  def window_meta
    {
      can_reply: @conversation.can_reply?,
      messaging_window_closes_at: Finture::MessagingWindow.closes_at(@conversation)&.iso8601,
      timezone: Finture::ScheduledMessage::TIMEZONE
    }
  end

  def serialize(item)
    local = item.scheduled_at.in_time_zone(Finture::ScheduledMessage::TIMEZONE)
    {
      id: item.id,
      conversation_id: @conversation.display_id,
      content: item.content,
      status: item.status,
      scheduled_at: item.scheduled_at.iso8601,
      scheduled_at_local: local.strftime('%Y-%m-%dT%H:%M'),
      scheduled_at_label: local.strftime('%d/%m/%Y %H:%M'),
      cancel_on_reply: item.cancel_on_reply,
      cancel_reason: item.cancel_reason,
      error_message: item.error_message,
      sent_at: item.sent_at&.iso8601,
      message_id: item.message_id,
      user: item.user && { id: item.user.id, name: item.user.available_name, thumbnail: item.user.avatar_url },
      created_at: item.created_at.iso8601
    }
  end
end
