class Captain::AssistantMigration::InstructionClassifier < Captain::BaseTaskService
  RESPONSE_SCHEMA = Captain::AssistantMigration::InstructionClassifierSchema
  FEATURE = 'onboarding_content_generation'.freeze
  MAX_INSTRUCTIONS_LENGTH = 20_000

  pattr_initialize [:assistant!]

  def perform
    response = make_api_call(feature: FEATURE, messages: messages, schema: RESPONSE_SCHEMA)
    return error_response(response) if response[:error]

    {
      assistant: assistant_metadata,
      draft: normalized_payload(response[:message]),
      usage: response[:usage],
      request_messages: response[:request_messages]
    }
  end

  private

  def account
    assistant.account
  end

  def messages
    [
      { role: 'system', content: system_prompt },
      { role: 'user', content: user_prompt }
    ]
  end

  def system_prompt
    <<~PROMPT
      You are migrating Captain assistant instructions into a structured configuration.

      Classify the existing assistant instructions into these sections:
      1. Business/Product Context
      2. Response Guidelines
      3. Guardrails
      4. Scenarios/Procedures
      5. Conversation Messages
      6. FAQs/Documents Candidates
      7. Needs Review

      Rules:
      - Preserve behavior as closely as possible.
      - Do not duplicate the same content across sections.
      - Do not rewrite customer-facing message copy unless necessary to classify an exact copy from instructions.
      - Existing welcome_message, handoff_message, and resolution_message are provided separately and should not be rewritten.
      - Only create scenarios for clear multi-step workflows, routing logic, qualification, handoff behavior, or tool-use procedures.
      - Do not classify simple tone, language, answer length, or short-reply rules as scenarios.
      - Product facts, pricing, policies, setup steps, and troubleshooting content should become FAQs/Documents candidates, not trusted approved knowledge.
      - If unsure, place content in Needs Review with a reason.
      - Use "high", "medium", or "low" confidence values only.
      - Return data that matches the provided schema.
    PROMPT
  end

  def user_prompt
    JSON.pretty_generate(assistant_payload)
  end

  def assistant_payload
    {
      assistant_id: assistant.id,
      account_id: assistant.account_id,
      account_name: assistant.account.name,
      name: assistant.name,
      description: assistant.description,
      product_name: assistant.config['product_name'],
      instructions: truncated_instructions,
      welcome_message: assistant.config['welcome_message'],
      handoff_message: assistant.config['handoff_message'],
      resolution_message: assistant.config['resolution_message'],
      existing_response_guidelines: assistant.response_guidelines || [],
      existing_guardrails: assistant.guardrails || [],
      existing_scenarios: existing_scenarios,
      feature_settings: feature_settings
    }
  end

  def truncated_instructions
    instructions = assistant.config['instructions'].to_s
    return instructions if instructions.length <= MAX_INSTRUCTIONS_LENGTH

    "#{instructions.first(MAX_INSTRUCTIONS_LENGTH)}\n\n[TRUNCATED]"
  end

  def existing_scenarios
    assistant.scenarios.map do |scenario|
      {
        id: scenario.id,
        title: scenario.title,
        description: scenario.description,
        instruction: scenario.instruction,
        enabled: scenario.enabled
      }
    end
  end

  def feature_settings
    assistant.config.slice(
      'feature_faq',
      'feature_memory',
      'feature_citation',
      'feature_contact_attributes',
      'temperature'
    )
  end

  def normalized_payload(message)
    payload = message.is_a?(Hash) ? message.deep_symbolize_keys : {}
    payload.reverse_merge(
      business_product_context: [],
      response_guidelines: [],
      guardrails: [],
      scenarios_procedures: [],
      conversation_messages: {},
      faq_document_candidates: [],
      needs_review: [],
      classification_notes: []
    )
  end

  def assistant_metadata
    {
      id: assistant.id,
      name: assistant.name,
      account_id: assistant.account_id,
      account_name: assistant.account.name,
      inbox_count: assistant.captain_inboxes.size,
      instruction_length: assistant.config['instructions'].to_s.length,
      original_instructions: assistant.config['instructions'].to_s,
      welcome_message: assistant.config['welcome_message'].to_s,
      handoff_message: assistant.config['handoff_message'].to_s,
      resolution_message: assistant.config['resolution_message'].to_s
    }
  end

  def error_response(response)
    {
      assistant: assistant_metadata,
      error: response[:error],
      error_code: response[:error_code],
      request_messages: response[:request_messages]
    }
  end

  def event_name
    'assistant_migration_instruction_classifier'
  end

  def captain_tasks_enabled?
    true
  end

  def counts_toward_usage?
    false
  end

  def build_follow_up_context?
    false
  end
end
