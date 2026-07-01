class Conversations::UnreadCounts::FilterQueryCounter < Conversations::FilterService
  MALFORMED_QUERY_ERRORS = [NoMethodError, TypeError].freeze
  NUMERIC_ATTRIBUTE_KEYS = %w[assignee_id inbox_id].freeze
  NUMERIC_DATA_TYPES = %w[number numeric].freeze
  VALUELESS_FILTER_OPERATORS = %w[is_present is_not_present].freeze

  def initialize(account:, user:, query:)
    super(query.with_indifferent_access, user, account)
  end

  def perform
    return unless valid_query?
    return unless valid_typed_values?

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

  def valid_typed_values?
    @params[:payload].all? do |query_hash|
      next true if VALUELESS_FILTER_OPERATORS.include?(query_hash[:filter_operator])

      attribute_key = query_hash[:attribute_key]
      data_type = @filters.dig('conversations', attribute_key, 'data_type').to_s.downcase
      next true unless numeric_filter?(attribute_key, data_type)

      valid_numeric_values?(query_hash[:values], data_type)
    end
  end

  def numeric_filter?(attribute_key, data_type)
    NUMERIC_ATTRIBUTE_KEYS.include?(attribute_key) || NUMERIC_DATA_TYPES.include?(data_type)
  end

  def valid_numeric_values?(values, data_type)
    Array.wrap(values).all? do |value|
      data_type == 'numeric' ? BigDecimal(value.to_s, exception: false) : Integer(value.to_s, exception: false)
    end
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
