# frozen_string_literal: true

# Base service for LLM operations using RubyLLM.
# New features should inherit from this class.
class Llm::BaseAiService
  DEFAULT_MODEL = Llm::Config::DEFAULT_MODEL
  DEFAULT_TEMPERATURE = 1.0

  attr_reader :model, :temperature

  def initialize
    Llm::Config.initialize!
    setup_model
    setup_temperature
  end

  def chat(model: @model, temperature: @temperature)
    RubyLLM.chat(model: model).with_temperature(temperature)
  end

  private

  # Strips markdown code fences (```json ... ``` or ``` ... ```) that some
  # LLM providers/gateways wrap around JSON responses despite response_format hints.
  def sanitize_json_response(response)
    return response if response.nil?

    response.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
  end

  def setup_model
    @model = Captain::ModelResolver.resolve(model_feature, default: DEFAULT_MODEL)
  end

  # Feature key used to resolve installation level per-feature model overrides.
  # Subclasses override this with their feature (e.g. 'contact_notes').
  def model_feature
    nil
  end

  # Overrides the resolved model with an account level Captain model override
  # when one is configured for the given feature. Subclasses call this after
  # their account is available, since setup_model runs before assignment.
  def apply_model_override(account, feature_key)
    override = account&.captain_model_override(feature_key)
    @model = override if override.present?
  end

  def setup_temperature
    @temperature = DEFAULT_TEMPERATURE
  end
end
