# frozen_string_literal: true

# Base service for LLM operations using RubyLLM.
# New features should inherit from this class.
class Llm::BaseAiService
  DEFAULT_MODEL = Llm::Config::DEFAULT_MODEL
  DEFAULT_TEMPERATURE = 1.0

  attr_reader :model, :provider, :temperature

  def initialize(feature: nil, account: nil, fallback_model: nil)
    @llm_feature = feature
    @llm_account = account
    @fallback_model = fallback_model

    Llm::Config.initialize!
    setup_model
    setup_temperature
  end

  def chat(model: @model, temperature: @temperature)
    chat = RubyLLM.chat(model: model, provider: provider_for_model(model), assume_model_exists: true).with_temperature(temperature)
    Llm::ProviderChat.new(chat, provider: provider_for_model(model))
  end

  private

  # Strips markdown code fences (```json ... ``` or ``` ... ```) that some
  # LLM providers/gateways wrap around JSON responses despite response_format hints.
  def sanitize_json_response(response)
    return response if response.nil?

    response.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
  end

  def setup_model
    route = feature_route
    if account_override_route?(route)
      @model = route[:model]
      return setup_provider(route)
    end

    @model = @fallback_model.presence || installation_model.presence || route&.dig(:model) || DEFAULT_MODEL
    setup_provider(route)
  end

  def feature_route
    return if @llm_feature.blank?

    Llm::FeatureRouter.resolve(feature: @llm_feature, account: @llm_account)
  end

  def account_override_route?(route)
    route&.dig(:source) == :account_override
  end

  def installation_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
  end

  def setup_provider(route)
    @provider = provider_for_model(@model, route&.dig(:provider))
  end

  def provider_for_model(model, fallback_provider = Llm::Config::DEFAULT_PROVIDER)
    Llm::Models.provider_for(model) || fallback_provider || Llm::Config::DEFAULT_PROVIDER
  end

  def setup_temperature
    @temperature = DEFAULT_TEMPERATURE
  end
end
