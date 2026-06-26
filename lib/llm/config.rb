require 'ruby_llm'
require_relative 'provider_config'

module Llm::Config
  extend Llm::ProviderConfig

  DEFAULT_MODEL = 'gpt-4.1-mini'.freeze
  DEFAULT_PROVIDER = 'openai'.freeze

  class << self
    def initialized? = @initialized ||= false

    def initialize!
      return if @initialized

      configure_ruby_llm
      @initialized = true
    end

    def reset! = @initialized = false

    def with_api_key(api_key, provider: DEFAULT_PROVIDER, api_base: nil, config_values: nil)
      initialize!
      context = RubyLLM.context do |config|
        values = config_values || provider_config_values(provider).merge(
          :"#{provider}_api_key" => api_key,
          :"#{provider}_api_base" => api_base
        ).compact
        configure_provider(config, provider: provider, config_values: values)
      end

      yield context
    end

    def with_provider(provider:, config_values: provider_config_values(provider))
      initialize!
      context = RubyLLM.context do |config|
        configure_provider(config, provider: provider, config_values: config_values)
      end

      yield context
    end

    private

    def configure_ruby_llm
      RubyLLM.configure do |config|
        provider_options.each_key do |provider|
          configure_provider(config, provider: provider, config_values: provider_config_values(provider))
        end
        config.model_registry_file = Rails.root.join('config/llm_models.json').to_s
        config.logger = Rails.logger
      end
    end
  end
end
