# Monta a linha do tempo de um contato: cada conversa (mais recente primeiro)
# com quando abriu, quando fechou e o resumo gerado pela IA (sdr_resumo).
#
# "Fechou" depende do tipo da caixa:
#   - comercial: momento do desfecho ganho/perdido (sdr_outcome_at);
#   - resolvida (qualquer caixa): último evento conversation_resolved — cai para
#     last_activity_at quando a conversa é anterior aos reporting events.
# Conversa em aberto não tem closed_at.
class Finture::ContactTimelineService
  TIMELINE_LIMIT = 100

  def initialize(contact:, user:, account:)
    @contact = contact
    @user = user
    @account = account
  end

  def perform
    conversations = scope.order(created_at: :desc).limit(TIMELINE_LIMIT).to_a
    resolved_at = resolved_at_by_conversation(conversations)
    types = kanban_types(conversations)

    {
      contact: @contact,
      entries: conversations.map do |conversation|
        {
          conversation: conversation,
          kanban_type: types[conversation.inbox_id] || Finture::InboxConfig::DEFAULT_TYPE,
          closed_at: closed_at(conversation, resolved_at[conversation.id])
        }
      end
    }
  end

  private

  def scope
    conversations = @account.conversations.where(contact_id: @contact.id)
    conversations = Conversations::PermissionFilterService.new(conversations, @user, @account).perform
    conversations.includes(:inbox, :taggings, assignee: { avatar_attachment: :blob })
  end

  def resolved_at_by_conversation(conversations)
    resolved_ids = conversations.select(&:resolved?).map(&:id)
    return {} if resolved_ids.empty?

    ReportingEvent.where(account_id: @account.id, name: 'conversation_resolved', conversation_id: resolved_ids)
                  .group(:conversation_id)
                  .maximum(:created_at)
  end

  def kanban_types(conversations)
    Finture::InboxConfig.where(inbox_id: conversations.map(&:inbox_id).uniq).pluck(:inbox_id, :kanban_type).to_h
  end

  def closed_at(conversation, resolved_at)
    outcome_at = conversation.custom_attributes&.dig('sdr_outcome_at').to_i
    return Time.zone.at(outcome_at) if outcome_at.positive?
    return unless conversation.resolved?

    resolved_at || conversation.last_activity_at
  end
end
