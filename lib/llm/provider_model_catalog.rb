module Llm::ProviderModelCatalog
  def installation_model(provider: provider_for_feature(nil))
    model = InstallationConfig.find_by(name: Llm::ProviderConfig::MODEL_CONFIG_KEY)&.value.presence
    return model if model_provider?(model, provider)

    legacy_model = InstallationConfig.find_by(name: Llm::ProviderConfig::LEGACY_OPENAI_MODEL_CONFIG_KEY)&.value.presence
    return legacy_model if provider == Llm::Config::DEFAULT_PROVIDER && model_provider?(legacy_model, provider)
  end

  def provider_default_model_options(provider = Llm::Config.current_provider)
    models_for_provider(provider).index_with do |model_name|
      model = model_config(model_name)
      model['display_name'] || model_name
    end
  end

  private

  def provider_for_feature(feature)
    return Llm::Config::DEFAULT_PROVIDER if openai_only_feature?(feature)

    Llm::Config.current_provider
  end

  def configured_models_for(feature, provider:)
    (features.dig(feature.to_s, 'models') || []).select do |model_name|
      supported_model?(model_name) && model_provider?(model_name, provider)
    end
  end

  def provider_models_for(feature, provider:)
    return [] if openai_only_feature?(feature)
    return [] if provider == Llm::Config::DEFAULT_PROVIDER

    models_for_provider(provider)
  end

  def models_for_provider(provider)
    configured_provider_models = models.filter_map do |model_name, config|
      model_name if config['provider'] == provider.to_s && chat_model?(model_name)
    end

    (configured_provider_models + ruby_llm_provider_models(provider)).uniq
  end

  def ruby_llm_provider_models(provider)
    return [] if provider.to_s == Llm::Config::DEFAULT_PROVIDER

    RubyLLM.models.by_provider(provider.to_s).chat_models.map(&:id)
  end

  def chat_model?(model_name)
    Llm::Models::OPENAI_ONLY_FEATURES.none? { |feature| features.dig(feature, 'models')&.include?(model_name) }
  end

  def model_provider?(model_name, provider)
    provider_for(model_name) == provider.to_s
  end

  def openai_only_feature?(feature)
    Llm::Models::OPENAI_ONLY_FEATURES.include?(feature.to_s)
  end
end
