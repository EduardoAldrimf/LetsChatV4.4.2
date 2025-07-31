class FlipChatwootV4DefaultFeatureFlagInstallationConfig < ActiveRecord::Migration[7.0]
  def up
    # Update the default feature flag config to enable chatwoot_v4
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    if config && config.value.present?
      features = config.value.map do |f|
        if f['name'] == 'chatwoot_v4'
          f.merge('enabled' => true)
        else
          f
        end
      end
      config.value = features
      config.save!
    end

    # Temporarily bypass the settings validation
    Account.class_eval do
      def settings
        # Return empty hash to avoid NoMethodError
        {}
      end
    end

    # Enable chatwoot_v4 for all accounts in batches of 100
    # We use update_all to skip validations and callbacks
    # rubocop:disable Rails/SkipsModelValidations
    Account.update_all("feature_flags = feature_flags | #{1 << 41}")  # chatwoot_v4 is the 42nd feature (index 41)
    # rubocop:enable Rails/SkipsModelValidations

    GlobalConfig.clear_cache
  end
end
