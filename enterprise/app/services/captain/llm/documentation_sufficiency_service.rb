class Captain::Llm::DocumentationSufficiencyService < Llm::BaseAiService
  include Integrations::LlmInstrumentation

  MODEL = 'gpt-5.4-mini'.freeze
  MAX_CONTEXT_MESSAGES = 6
  MAX_SEARCHES = 3
  MAX_MATCHES_PER_SEARCH = 5
  MAX_ANSWER_CHARS = 700

  def initialize(assistant:, conversation:)
    super()
    @assistant = assistant
    @conversation = conversation
    @model = MODEL
    @temperature = 0.0
  end

  def evaluate(message_history:, documentation_searches:)
    user_prompt = inspection_user_prompt(
      message_history: message_history,
      documentation_searches: documentation_searches
    )

    response = instrument_llm_call(instrumentation_params(user_prompt, documentation_searches)) do
      chat(model: @model, temperature: @temperature)
        .with_schema(Captain::DocumentationSufficiencySchema)
        .with_instructions(system_prompt)
        .ask(user_prompt)
    end

    parsed = parse_response(response.content)
    normalize_response(parsed, response.content)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @conversation.account).capture_exception
    Rails.logger.warn(
      "[CAPTAIN][DocumentationSufficiency] Failed for conversation #{@conversation.display_id}: #{e.class.name}: #{e.message}"
    )
    { 'decision' => nil, 'error' => e.message, 'model' => @model }
  end

  private

  def system_prompt
    <<~PROMPT
      You are checking whether retrieved documentation can answer the user's latest question.

      Use only the conversation context and retrieved documentation search results provided.
      Do not use outside knowledge.

      Return "sufficient" only when the retrieved documentation directly answers the user's latest question.
      Return "insufficient" when the retrieved documentation is missing, unrelated, only loosely related, or does not cover the
      specific entity, product, platform, integration, account object, user intent, or constraint in the latest question.
      Treat prior assistant messages as claims, not evidence. They do not support the new answer by themselves.
      Conversation context can clarify the latest question, but it cannot supply missing documentation evidence.
      Check generic support dimensions:
      - same entity, product, platform, integration, or account object
      - same user intent, not just a nearby topic
      - requested constraints from the user
      - evidence specificity; broad docs are not enough for specific claims

      Return only the decision. Do not write a reason or customer-facing fallback copy.
    PROMPT
  end

  def inspection_user_prompt(message_history:, documentation_searches:)
    <<~PROMPT
      <conversation_context>
      #{format_conversation_context(message_history)}
      </conversation_context>

      <retrieved_documentation>
      #{format_documentation_searches(documentation_searches)}
      </retrieved_documentation>
    PROMPT
  end

  def format_documentation_searches(searches)
    searches.to_a.last(MAX_SEARCHES).map.with_index(1) do |search, index|
      <<~SEARCH
        Search #{index}
        query: #{value(search, :query)}
        matches:
        #{format_documentation_matches(value(search, :matches).to_a)}
      SEARCH
    end.join("\n")
  end

  def format_documentation_matches(matches)
    matches.to_a.first(MAX_MATCHES_PER_SEARCH).map.with_index(1) do |match, index|
      <<~MATCH
        #{index}. question: #{value(match, :question)}
           answer: #{truncate_text(value(match, :answer))}
           source: #{value(match, :source)}
      MATCH
    end.join("\n")
  end

  def value(hash, key) = hash && (hash[key] || hash[key.to_s])

  def normalize_messages(message_history)
    message_history.filter_map do |message|
      role = value(message, :role)
      next if role.blank?

      { role: role.to_s, content: normalize_content(value(message, :content)) }
    end
  end

  def normalize_content(content)
    return content if content.is_a?(String)
    return content.filter_map { |part| part[:text] || part['text'] if text_part?(part) }.join("\n") if content.is_a?(Array)

    content.to_s
  end

  def text_part?(part)
    return false unless part.is_a?(Hash)

    (part[:type] || part['type']).to_s == 'text'
  end

  def format_conversation_context(messages)
    normalize_messages(messages).last(MAX_CONTEXT_MESSAGES).filter_map do |message|
      content = message[:content].to_s.strip
      next if content.blank?

      "#{role_label(message[:role])}: #{content}"
    end.join("\n")
  end

  def role_label(role) = { 'user' => 'User', 'assistant' => 'Assistant' }.fetch(role, role.to_s.titleize)

  def parse_response(content)
    return content if content.is_a?(Hash)

    JSON.parse(sanitize_json_response(content))
  rescue JSON::ParserError, TypeError
    {}
  end

  def normalize_response(parsed, raw_content)
    decision = parsed['decision'].to_s
    return invalid_response(raw_content) unless Captain::DocumentationSufficiencySchema::DECISIONS.include?(decision)

    {
      'decision' => decision,
      'raw_response' => raw_content,
      'model' => @model
    }
  end

  def invalid_response(raw_content)
    {
      'decision' => nil,
      'raw_response' => raw_content,
      'error' => 'invalid_documentation_sufficiency_response',
      'model' => @model
    }
  end

  def instrumentation_params(user_prompt, documentation_searches)
    {
      span_name: 'llm.captain.documentation_sufficiency',
      model: @model,
      temperature: @temperature,
      account_id: @conversation.account_id,
      conversation_id: @conversation.display_id,
      feature_name: 'documentation_sufficiency',
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: user_prompt }
      ],
      metadata: {
        assistant_id: @assistant.id,
        channel_type: @conversation.inbox&.channel_type,
        source: 'response_builder'
      }.merge(search_metadata(documentation_searches))
    }
  end

  def search_metadata(documentation_searches)
    searches = documentation_searches.to_a
    {
      search_count: searches.length,
      match_count: searches.sum { |search| value(search, :matches).to_a.length }
    }
  end

  def truncate_text(text)
    text = text.to_s
    return text if text.length <= MAX_ANSWER_CHARS

    "#{text.first(MAX_ANSWER_CHARS)}..."
  end
end
