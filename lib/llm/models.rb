require_relative 'provider_model_catalog'

module Llm::Models
  extend Llm::ProviderModelCatalog

  CONFIG = YAML.load_file(Rails.root.join('config/llm.yml')).freeze
  OPENAI_ONLY_FEATURES = %w[audio_transcription help_center_search].freeze

  class << self
    def providers
      Llm::Config.provider_options.transform_values { |display_name| { 'display_name' => display_name } }
    end

    def models = CONFIG.fetch('models')
    def features = CONFIG.fetch('features')
    def feature_keys = features.keys

    def feature?(feature)
      features.key?(feature.to_s)
    end

    def default_model_for(feature)
      installation_default = installation_model
      return installation_default if valid_model_for?(feature, installation_default)

      feature_default = features.dig(feature.to_s, 'default')
      return feature_default if valid_model_for?(feature, feature_default)

      models_for(feature).first
    end

    def models_for(feature, provider: provider_for_feature(feature))
      (configured_models_for(feature, provider: provider) + provider_models_for(feature, provider: provider)).uniq
    end

    def valid_model_for?(feature, model_name, provider: provider_for_feature(feature))
      return false if model_name.blank?

      models_for(feature, provider: provider).include?(model_name.to_s)
    end

    def model_config(model_name)
      models[model_name.to_s] || ruby_llm_model_config(model_name)
    end

    def provider_for(model_name)
      models.dig(model_name.to_s, 'provider') || ruby_llm_model(model_name)&.provider
    end

    def supported_provider?(provider)
      providers.key?(provider.to_s) && Llm::Config.ruby_llm_provider_supported?(provider)
    end

    def supported_model?(model_name)
      config = model_config(model_name)
      return false unless config

      supported_provider?(config['provider'])
    end

    def feature_config(feature_key)
      feature = features[feature_key.to_s]
      return nil unless feature

      provider = provider_for_feature(feature_key)

      {
        models: models_for(feature_key, provider: provider).map do |model_name|
          model = model_config(model_name)
          {
            id: model_name,
            display_name: model['display_name'],
            provider: model['provider'],
            coming_soon: model['coming_soon'],
            credit_multiplier: model['credit_multiplier']
          }
        end,
        default: default_model_for(feature_key),
        provider: provider
      }
    end

    private

    def ruby_llm_model_config(model_name)
      model = ruby_llm_model(model_name)
      return unless model

      {
        'provider' => model.provider,
        'display_name' => model.name
      }
    end

    def ruby_llm_model(model_name)
      RubyLLM.models.find(model_name.to_s)
    rescue StandardError
      nil
    end
  end
end
