module Captain::Conversation::DocumentationSupportGate
  private

  def check_documentation_support(message_history, chat_service: nil)
    return unless documentation_support_gate_enabled?
    return unless customer_reply?

    searches = documentation_searches(message_history)
    return if documentation_sufficiency_checked_in_tool?(searches)

    review = documentation_support_review(message_history, searches)
    apply_documentation_support_decision(review, message_history, chat_service)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
    Rails.logger.warn(
      "[CAPTAIN][ResponseBuilderJob] Documentation support check failed for account=#{account.id} " \
      "conversation=#{@conversation.display_id}: #{e.class.name}: #{e.message}"
    )
  end

  def documentation_support_gate_enabled?
    ActiveModel::Type::Boolean.new.cast(@assistant.config['documentation_sufficiency_gate_enabled'])
  end

  def customer_reply?
    @response.present? &&
      @response['response'].present? &&
      @response['response'] != 'conversation_handoff' &&
      !@response['handoff_tool_called']
  end

  def documentation_support_review(message_history, searches)
    Captain::Llm::DocumentationSufficiencyService.new(
      assistant: @assistant,
      conversation: @conversation
    ).evaluate(
      message_history: message_history,
      documentation_searches: searches
    )
  end

  def documentation_sufficiency_checked_in_tool?(searches)
    searches.any? { |search| (search[:documentation_sufficiency] || search['documentation_sufficiency']).present? }
  end

  def documentation_searches(message_history)
    searches = @response['documentation_searches'].to_a
    return searches if searches.present?

    [missing_documentation_search(last_user_message(message_history))]
  end

  def missing_documentation_search(query)
    {
      query: query,
      queries: [query],
      matches: []
    }
  end

  def last_user_message(message_history)
    message = message_history.reverse.find { |item| (item[:role] || item['role']).to_s == 'user' }
    message && (message[:content] || message['content']).to_s
  end

  def apply_documentation_support_decision(review, message_history, chat_service)
    return unless review['decision'] == 'insufficient'

    if chat_service
      @response.replace(chat_service.generate_documentation_gap_response(message_history: message_history))
    else
      @response['response'] = default_documentation_fallback
    end

    @response.merge!(
      'action' => 'continue',
      'action_reason' => 'missing_docs_bounded_answer',
      'action_source' => 'documentation_support',
      'documentation_sufficiency_model' => review['model']
    )
  end

  def default_documentation_fallback
    'I do not have enough information to answer that. Would you like me to connect you with support?'
  end
end
