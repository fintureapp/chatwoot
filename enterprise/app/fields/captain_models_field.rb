require 'administrate/field/base'

class CaptainModelsField < Administrate::Field::Base
  # Account-level Captain model overrides are restricted to these product features
  # by AccountSettingsSchema. Each renders a dropdown; a blank value means the
  # account falls back to the installation default for that feature.
  FEATURE_KEYS = %w[editor assistant copilot label_suggestion audio_transcription help_center_search].freeze

  PROVIDER_NAMES = { 'openai' => 'OpenAI', 'anthropic' => 'Anthropic', 'gemini' => 'Gemini' }.freeze

  def self.provider_name(key)
    PROVIDER_NAMES[key.to_s] || key.to_s.titleize
  end

  def selected_models
    (data.presence || {}).to_h.stringify_keys
  end

  # Rich choice metadata (provider, credit cost, availability) for each model
  # allowed for a feature — used to render the rich dropdown. Only OpenAI models
  # are offered for selection today.
  def model_choices(feature_key)
    config = Llm::Models.feature_config(feature_key)
    return [] if config.blank?

    config[:models].select { |model| model[:provider].to_s == 'openai' }.map do |model|
      { id: model[:id], name: model[:display_name], provider: model[:provider],
        cost: model[:credit_multiplier], coming_soon: model[:coming_soon] }
    end
  end

  def selected_choice(feature_key)
    value = selected_models[feature_key]
    return nil if value.blank?

    model_choices(feature_key).find { |model| model[:id] == value }
  end
end
