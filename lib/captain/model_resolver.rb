# Resolves which LLM model an OpenAI/Captain call should use, applying overrides
# in priority order so a model can be customized per account or per installation
# without changing any call site's behavior when nothing is configured:
#
#   1. Account level override   (Account#captain_model_override, product features only)
#   2. Installation per-feature (CAPTAIN_FEATURE_MODELS, set by superadmin)
#   3. Installation global      (CAPTAIN_OPEN_AI_MODEL, legacy single value)
#   4. The call site's default  (its current value — behaviour preserving)
#
# Pass apply_global: false for call sites that historically ignored the global
# CAPTAIN_OPEN_AI_MODEL (audio transcription, embeddings, and intentionally pinned
# models) so setting the global never silently changes them.
module Captain::ModelResolver
  FEATURE_CONFIG_KEY = 'CAPTAIN_FEATURE_MODELS'.freeze
  GLOBAL_CONFIG_KEY = 'CAPTAIN_OPEN_AI_MODEL'.freeze

  module_function

  def resolve(feature, default:, account: nil, apply_global: true)
    account_override(account, feature) ||
      installation_feature_override(feature) ||
      (apply_global ? global_override : nil) ||
      default
  end

  def account_override(account, feature)
    return nil unless feature.present? && account.respond_to?(:captain_model_override)

    account.captain_model_override(feature)
  end

  def installation_feature_override(feature)
    return nil if feature.blank?

    models = InstallationConfig.find_by(name: FEATURE_CONFIG_KEY)&.value
    models.is_a?(Hash) ? models[feature.to_s].presence : nil
  end

  def global_override
    InstallationConfig.find_by(name: GLOBAL_CONFIG_KEY)&.value.presence
  end
end
