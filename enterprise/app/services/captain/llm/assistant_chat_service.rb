class Captain::Llm::AssistantChatService < Llm::BaseAiService
  include Captain::ChatHelper
  attr_reader :documentation_searches

  def initialize(assistant: nil, conversation: nil, source: nil)
    super()

    @assistant = assistant
    @conversation = conversation
    @conversation_id = conversation&.display_id
    @source = source

    @messages = [system_message]
    @response = ''
    @documentation_searches = []
    @tools = build_tools
  end

  # additional_message: A single message (String) from the user that should be appended to the chat.
  #                    It can be an empty String or nil when you only want to supply historical messages.
  # message_history:   An Array of already formatted messages that provide the previous context.
  # role:              The role for the additional_message (defaults to `user`).
  #
  # NOTE: Parameters are provided as keyword arguments to improve clarity and avoid relying on
  # positional ordering.
  def generate_response(additional_message: nil, message_history: [], role: 'user', &after_response)
    @messages += message_history
    @messages << { role: role, content: additional_message } if additional_message.present?
    @after_response = after_response
    request_chat_completion
  ensure
    @after_response = nil
  end

  def generate_documentation_gap_response(message_history:)
    previous_messages = @messages
    previous_tools = @tools
    previous_after_response = @after_response

    discard_deferred_llm_generations
    @messages = [system_message, documentation_gap_instruction] + message_history
    @tools = []
    @after_response = nil

    request_chat_completion
  ensure
    @messages = previous_messages
    @tools = previous_tools
    @after_response = previous_after_response
  end

  private

  def build_tools
    tools = [
      Captain::Tools::SearchDocumentationService.new(
        @assistant,
        user: nil,
        on_search: ->(search) { @documentation_searches << search },
        message_history: -> { conversation_messages },
        conversation: @conversation
      )
    ]
    return tools unless custom_tools_enabled?

    tools + @assistant.account.captain_custom_tools.enabled.map do |ct|
      ct.tool(@assistant, base_class: Captain::Tools::CustomHttpTool, conversation: @conversation)
    end
  end

  def system_message
    {
      role: 'system',
      content: Captain::Llm::SystemPromptsService.assistant_response_generator(
        @assistant.name, @assistant.config['product_name'], @assistant.config.merge('timezone' => inbox_timezone),
        contact: contact_attributes,
        custom_tools: custom_tools_metadata
      )
    }
  end

  def documentation_gap_instruction
    {
      role: 'system',
      content: <<~PROMPT
        [Documentation Support]
        The retrieved documentation was not sufficient to answer the user's latest question.
        Do not answer the factual question or cite the retrieved documentation.
        Respond briefly in the user's language.
        Ask one clarifying question if that would help, or offer a handoff.
        Return the normal JSON response.
      PROMPT
    }
  end

  def custom_tools_metadata
    return [] unless custom_tools_enabled?

    @assistant.account.captain_custom_tools.enabled.map do |ct|
      { name: ct.slug, description: ct.description }
    end
  end

  def custom_tools_enabled?
    @assistant.account.feature_enabled?('custom_tools')
  end

  def contact_attributes
    return nil unless @conversation&.contact
    return nil unless @assistant&.feature_contact_attributes

    @conversation.contact.attributes.symbolize_keys.slice(
      :id, :name, :email, :phone_number, :identifier, :custom_attributes
    )
  end

  def inbox_timezone
    @conversation&.inbox&.timezone.presence || 'UTC'
  end

  def persist_message(message, message_type = 'assistant')
    # No need to implement
  end

  def feature_name
    'assistant'
  end

  def after_chat_response(response)
    @after_response&.call(response)
  end
end
