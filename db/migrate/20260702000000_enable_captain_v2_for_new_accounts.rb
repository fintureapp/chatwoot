class EnableCaptainV2ForNewAccounts < ActiveRecord::Migration[7.1]
  def up
    config = InstallationConfig.find_by!(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    features = config.value

    %w[captain_integration captain_integration_v2].each do |feature_name|
      features.find { |feature| feature['name'] == feature_name }['enabled'] = true
    end

    config.update!(value: features)
    GlobalConfig.clear_cache
  end
end
