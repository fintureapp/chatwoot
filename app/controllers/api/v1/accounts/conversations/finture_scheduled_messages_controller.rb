# Mensagens agendadas da conversa. Horário chega como hora de parede em
# America/Sao_Paulo ("2026-10-21T15:30") e volta em ISO 8601 (UTC) + a mesma
# hora local já formatada, para a UI não depender do fuso do navegador.
# O agendamento é texto livre (`content`) OU template do WhatsApp
# (`template_params`, mesmo formato da caixa de resposta; `content` = texto renderizado).
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
      cancel_on_reply: cancel_on_reply_param(true),
      template_params: template_params_param
    )
    Finture::ScheduledMessageService.new(scheduled_message: item).schedule!
    render json: serialize(item).merge(meta: window_meta)
  rescue CustomExceptions::Base => e
    render_could_not_create_error(e.message)
  end

  def update
    Finture::ScheduledMessageService.new(scheduled_message: @scheduled_message).update!(update_attrs)
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

  # Só o que veio no request; `template_params` nulo troca o agendamento para texto livre.
  def update_attrs
    attrs = {}
    attrs[:content] = params[:content] if params.key?(:content)
    attrs[:scheduled_at] = parse_time if params[:scheduled_at].present?
    attrs[:cancel_on_reply] = cancel_on_reply_param(@scheduled_message.cancel_on_reply) if params.key?(:cancel_on_reply)
    attrs[:template_params] = template_params_param if params.key?(:template_params)
    attrs
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

  # Só as chaves que o envio de template usa; vazio/nulo = texto livre.
  def template_params_param
    raw = params[:template_params]
    return nil if raw.blank?

    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    raw.to_h.deep_stringify_keys.slice('name', 'category', 'language', 'namespace', 'processed_params')
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
      created_at: item.created_at.iso8601
    }.merge(serialize_details(item))
  end

  def serialize_details(item)
    {
      kind: item.template? ? 'template' : 'text',
      template_params: item.template_params,
      user: item.user && { id: item.user.id, name: item.user.available_name, thumbnail: item.user.avatar_url }
    }
  end
end
