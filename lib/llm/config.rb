require 'ruby_llm'

module Llm::Config
  DEFAULT_MODEL = 'gpt-4.1-mini'.freeze
  DEFAULT_PROVIDER = 'openai'.freeze

  PROVIDER_CONFIGS = {
    'openai' => {
      api_key: 'CAPTAIN_OPEN_AI_API_KEY',
      api_base: 'CAPTAIN_OPEN_AI_ENDPOINT'
    },
    'anthropic' => {
      api_key: 'CAPTAIN_ANTHROPIC_API_KEY',
      api_base: 'CAPTAIN_ANTHROPIC_API_BASE'
    },
    'gemini' => {
      api_key: 'CAPTAIN_GEMINI_API_KEY',
      api_base: 'CAPTAIN_GEMINI_API_BASE'
    }
  }.freeze

  class << self
    def initialized? = @initialized ||= false

    def initialize!
      return if @initialized

      configure_ruby_llm
      @initialized = true
    end

    def reset! = @initialized = false

    def with_api_key(api_key, provider: DEFAULT_PROVIDER, api_base: nil)
      initialize!
      context = RubyLLM.context do |config|
        configure_provider(config, provider: provider, api_key: api_key, api_base: api_base)
      end

      yield context
    end

    def ruby_llm_provider_supported?(provider)
      RubyLLM::Provider.providers.key?(provider.to_s.to_sym)
    end

    def provider_options
      PROVIDER_CONFIGS.keys.each_with_object({}) do |provider, result|
        next unless ruby_llm_provider_supported?(provider)

        result[provider] = ruby_llm_provider_name(provider)
      end
    end

    def api_key_for(provider)
      installation_config_value(provider, :api_key)
    end

    def api_base_for(provider)
      api_base = installation_config_value(provider, :api_base).presence
      return if api_base.blank?

      normalized_api_base(provider, api_base)
    end

    def provider_configured?(provider)
      api_key_for(provider).present?
    end

    def openai_provider?(provider)
      provider.to_s == DEFAULT_PROVIDER
    end

    def supports_tools_and_schema?(provider)
      openai_provider?(provider)
    end

    def configure_provider(config, provider:, api_key:, api_base: nil)
      provider = provider.to_s
      options = provider_configuration_options(provider)
      api_key_option = :"#{provider}_api_key"
      api_base_option = :"#{provider}_api_base"

      set_config_value(config, api_key_option, api_key) if api_key.present? && options.include?(api_key_option)
      set_config_value(config, api_base_option, api_base) if api_base.present? && options.include?(api_base_option)
    end

    private

    def configure_ruby_llm
      RubyLLM.configure do |config|
        PROVIDER_CONFIGS.each_key do |provider|
          next unless ruby_llm_provider_supported?(provider)

          configure_provider(config, provider: provider, api_key: api_key_for(provider), api_base: api_base_for(provider))
        end
        config.model_registry_file = Rails.root.join('config/llm_models.json').to_s
        config.logger = Rails.logger
      end
    end

    def ruby_llm_provider_name(provider)
      RubyLLM::Provider.providers[provider.to_s.to_sym].name
    end

    def provider_configuration_options(provider)
      RubyLLM::Provider.providers[provider.to_s.to_sym]&.configuration_options || []
    end

    def set_config_value(config, option, value)
      setter = :"#{option}="
      config.public_send(setter, value) if config.respond_to?(setter)
    end

    def installation_config_value(provider, key)
      config_name = PROVIDER_CONFIGS.dig(provider.to_s, key)
      return if config_name.blank?

      InstallationConfig.find_by(name: config_name)&.value
    end

    def normalized_api_base(provider, api_base)
      endpoint = api_base.chomp('/').delete_suffix('/chat/completions')
      return "#{endpoint}/v1" if openai_provider?(provider) && endpoint.exclude?('/v1')

      endpoint
    end
  end
end
