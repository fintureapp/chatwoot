class Conversations::UnreadCounts::FilterQueryCounter < Conversations::FilterService
  MALFORMED_QUERY_ERRORS = [NoMethodError, TypeError].freeze

  def initialize(account:, user:, query:)
    super(query.with_indifferent_access, user, account)
  end

  def perform
    return unless valid_query?

    validate_query_operator
    query_builder(@filters['conversations']).count
  rescue *MALFORMED_QUERY_ERRORS
    nil
  end

  def base_relation
    Conversations::PermissionFilterService.new(unread_conversations, @user, @account).perform
  end

  private

  def valid_query?
    @params[:payload].is_a?(Array)
  end

  def unread_conversations
    @account.conversations
            .joins(:messages)
            .merge(Message.incoming.reorder(nil))
            .where(messages: { account_id: @account.id })
            .where(unread_since_last_seen_condition)
            .distinct
  end

  def unread_since_last_seen_condition
    conversations = Conversation.arel_table
    messages = Message.arel_table

    conversations[:agent_last_seen_at].eq(nil).or(messages[:created_at].gt(conversations[:agent_last_seen_at]))
  end
end
