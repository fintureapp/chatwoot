class EnableCaptainV2ForNewAccounts < ActiveRecord::Migration[7.1]
  def up
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?

    features = config.value
    captain_features = features.select { |f| %w[captain_integration captain_integration_v2].include?(f['name']) }
    return if captain_features.blank?

    captain_features.each { |feature| feature['enabled'] = true }
    config.update!(value: features)
    GlobalConfig.clear_cache
  end
end
