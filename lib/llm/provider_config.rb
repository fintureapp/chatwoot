require 'ruby_llm'

module Llm::ProviderConfig
  PROVIDER_CONFIG_PREFIX = 'CAPTAIN_LLM'.freeze
  PROVIDER_CONFIG_KEY = 'CAPTAIN_LLM_PROVIDER'.freeze
  MODEL_CONFIG_KEY = 'CAPTAIN_LLM_MODEL'.freeze
  LEGACY_OPENAI_MODEL_CONFIG_KEY = 'CAPTAIN_OPEN_AI_MODEL'.freeze

  LEGACY_CONFIG_KEYS = {
    openai_api_key: 'CAPTAIN_OPEN_AI_API_KEY',
    openai_api_base: 'CAPTAIN_OPEN_AI_ENDPOINT',
    anthropic_api_key: 'CAPTAIN_ANTHROPIC_API_KEY',
    anthropic_api_base: 'CAPTAIN_ANTHROPIC_API_BASE',
    gemini_api_key: 'CAPTAIN_GEMINI_API_KEY',
    gemini_api_base: 'CAPTAIN_GEMINI_API_BASE'
  }.freeze

  def ruby_llm_provider_supported?(provider)
    RubyLLM::Provider.providers.key?(provider.to_s.to_sym)
  end

  def provider_options
    RubyLLM::Provider.providers.keys.map(&:to_s).sort.index_with do |provider|
      ruby_llm_provider_name(provider)
    end
  end

  def provider_config_keys(provider = nil)
    ([PROVIDER_CONFIG_KEY, MODEL_CONFIG_KEY] + provider_config_options(provider).values).uniq
  end

  def provider_config_options(provider = nil)
    providers = provider.present? ? [provider.to_s] : provider_options.keys

    providers.each_with_object({}) do |provider_name, result|
      provider_configuration_options(provider_name).each do |option|
        result[option] = installation_config_name(option)
      end
    end
  end

  def current_provider
    provider = InstallationConfig.find_by(name: PROVIDER_CONFIG_KEY)&.value.presence
    return provider if provider_options.key?(provider)

    Llm::Config::DEFAULT_PROVIDER
  end

  def api_key_for(provider)
    provider_config_values(provider)[:"#{provider}_api_key"]
  end

  def api_base_for(provider)
    api_base = provider_config_values(provider)[:"#{provider}_api_base"].presence
    return if api_base.blank?

    normalized_api_base(provider, api_base)
  end

  def provider_configured?(provider)
    requirements = provider_configuration_requirements(provider)
    return false if requirements.blank?

    values = provider_config_values(provider)
    requirements.all? { |requirement| values[requirement].present? }
  end

  def openai_provider?(provider)
    provider.to_s == Llm::Config::DEFAULT_PROVIDER
  end

  def supports_tools_and_schema?(provider)
    openai_provider?(provider)
  end

  def provider_config_values(provider)
    provider = provider.to_s
    provider_configuration_options(provider).each_with_object({}) do |option, values|
      value = installation_config_value(option).presence
      value = normalized_api_base(provider, value) if option == :"#{provider}_api_base" && value.present?
      values[option] = value if value.present?
    end
  end

  def configure_provider(config, provider:, config_values:)
    options = provider_configuration_options(provider)
    config_values.each do |option, value|
      set_config_value(config, option, value) if value.present? && options.include?(option)
    end
  end

  private

  def ruby_llm_provider_name(provider)
    RubyLLM::Provider.providers[provider.to_s.to_sym].name
  end

  def provider_configuration_options(provider)
    RubyLLM::Provider.providers[provider.to_s.to_sym]&.configuration_options || []
  end

  def provider_configuration_requirements(provider)
    RubyLLM::Provider.providers[provider.to_s.to_sym]&.configuration_requirements || []
  end

  def set_config_value(config, option, value)
    setter = :"#{option}="
    config.public_send(setter, value) if config.respond_to?(setter)
  end

  def installation_config_value(option)
    InstallationConfig.find_by(name: installation_config_name(option))&.value
  end

  def installation_config_name(option)
    LEGACY_CONFIG_KEYS.fetch(option.to_sym) do
      "#{PROVIDER_CONFIG_PREFIX}_#{option.to_s.upcase}"
    end
  end

  def normalized_api_base(provider, api_base)
    endpoint = api_base.chomp('/').delete_suffix('/chat/completions')
    return "#{endpoint}/v1" if openai_provider?(provider) && endpoint.exclude?('/v1')

    endpoint
  end
end
