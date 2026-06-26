module Llm::Models
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
      default_model = features.dig(feature.to_s, 'default')
      return default_model if supported_model?(default_model)

      models_for(feature).first
    end

    def models_for(feature)
      (configured_models_for(feature) + provider_models_for(feature)).uniq
    end

    def valid_model_for?(feature, model_name)
      models_for(feature).include?(model_name.to_s)
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

      {
        models: models_for(feature_key).map do |model_name|
          model = model_config(model_name)
          {
            id: model_name,
            display_name: model['display_name'],
            provider: model['provider'],
            coming_soon: model['coming_soon'],
            credit_multiplier: model['credit_multiplier']
          }
        end,
        default: feature['default']
      }
    end

    private

    def configured_models_for(feature)
      (features.dig(feature.to_s, 'models') || []).select { |model_name| supported_model?(model_name) }
    end

    def provider_models_for(feature)
      return [] if openai_only_feature?(feature)

      provider = Llm::Config.current_provider
      return [] if provider == Llm::Config::DEFAULT_PROVIDER

      RubyLLM.models.by_provider(provider).chat_models.map(&:id)
    end

    def openai_only_feature?(feature)
      OPENAI_ONLY_FEATURES.include?(feature.to_s)
    end

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
