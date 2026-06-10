class Captain::Tools::SearchDocumentationService < Captain::Tools::BaseTool
  include Integrations::LlmInstrumentation
  skip_tool_execution_instrumentation

  def initialize(assistant, user: nil, on_search: nil, message_history: nil, conversation: nil)
    super(assistant, user: user)
    @on_search = on_search
    @message_history = message_history
    @conversation = conversation
  end

  def self.name
    'search_documentation'
  end
  description 'Search and retrieve documentation from knowledge base'

  param :query, desc: 'Search Query', required: true

  def execute(query:)
    Rails.logger.info { "#{self.class.name}: #{query}" }

    translated_query = Captain::Llm::TranslateQueryService
                       .new(account: assistant.account)
                       .translate(query, target_language: assistant.account.locale_english_name)

    instrument_documentation_search(query: translated_query, original_query: query) do
      format_search_result(search_documentation(translated_query))
    end
  end

  private

  def instrument_documentation_search(query:, original_query:, &)
    arguments = { query: query }
    arguments[:original_query] = original_query if original_query != query

    instrument_tool_call('search_documentation', arguments, &)
  end

  def write_search_metadata(result, documentation_sufficiency = nil)
    span = OpenTelemetry::Trace.current_span
    metadata = Captain::DocumentationSearchService.metadata(result)
    decision = documentation_sufficiency && (documentation_sufficiency[:decision] || documentation_sufficiency['decision'])
    metadata[:documentation_sufficiency] = decision if decision
    metadata.each do |key, value|
      span.set_attribute(format(ATTR_LANGFUSE_METADATA, key), value.to_s)
      span.set_attribute(format(ATTR_LANGFUSE_OBSERVATION_METADATA, key), value.to_s)
    end
  rescue StandardError => e
    Rails.logger.warn "#{self.class.name}: Failed to write search metadata: #{e.message}"
  end

  def search_documentation(query)
    Captain::DocumentationSearchService.new(
      scope: assistant.responses.approved,
      account_id: assistant.account_id
    ).search(query)
  end

  def format_search_result(result)
    serialized_result = Captain::DocumentationSearchService.serialize(result)
    documentation_sufficiency = evaluate_documentation_sufficiency(serialized_result)
    serialized_result[:documentation_sufficiency] = documentation_sufficiency if documentation_sufficiency.present?
    write_search_metadata(result, documentation_sufficiency)
    @on_search&.call(serialized_result)

    Captain::DocumentationSearchService.format_for_tool(
      result,
      no_results_message: 'No documentation found for the given query',
      documentation_sufficiency: documentation_sufficiency
    )
  end

  def evaluate_documentation_sufficiency(search)
    return unless documentation_sufficiency_enabled?
    return { 'decision' => 'insufficient', 'model' => nil } if search[:matches].blank?

    Captain::Llm::DocumentationSufficiencyService.new(
      assistant: assistant,
      conversation: @conversation
    ).evaluate(
      message_history: @message_history.call,
      documentation_searches: [search]
    )
  end

  def documentation_sufficiency_enabled?
    @conversation.present? &&
      @message_history.respond_to?(:call) &&
      ActiveModel::Type::Boolean.new.cast(assistant.config['documentation_sufficiency_gate_enabled'])
  end
end
