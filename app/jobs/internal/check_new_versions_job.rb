class Internal::CheckNewVersionsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    #return unless Rails.env.production?

    if migrations_pending?
      Rails.logger.warn 'Activation bypassed: pending migrations detected'
      return
    end

    #@instance_info = ChatwootHub.sync_with_hub
    #update_version_info
    check_mega_activation
  end

  private

  def update_version_info
    return if @instance_info['version'].blank?

    ::Redis::Alfred.set(::Redis::Alfred::LATEST_CHATWOOT_VERSION, @instance_info['version'])
  end

  def migrations_pending?
    ActiveRecord::Base.connection.migration_context.needs_migration?
  rescue StandardError => e
    Rails.logger.error "Error verifying migrations: #{e.message}"
    true
  end

  def check_mega_activation
    installation_identifier = InstallationConfig.find_or_create_by(name: 'INSTALLATION_IDENTIFIER') do |config|
      config.value = SecureRandom.uuid
    end.value

    installation_domain = ENV.fetch('FRONTEND_URL', nil)

    Rails.logger.info 'Checking New Version...'
    uri = URI.parse('https://control.chat2one.com/webhook/check-mega')
    params = { frontend_url: installation_domain, installation_identifier: installation_identifier }
    uri.query = URI.encode_www_form(params)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 60, read_timeout: 60) do |http|
      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = 'mega-License-Checker'
      http.request(request)
    end

    handle_mega_response(response)
  rescue Timeout::Error, SocketError => e
    Rails.logger.error "Network error during license check: #{e.message}"
    false
  end

  def handle_mega_response(response)
    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error "Activation failed with HTTP #{response.code}"
      return false
    end

    result = JSON.parse("{#{response.body}}")
    if result['valid']
      Rails.logger.info 'Activation completed successfully'
      true
    else
      Rails.logger.error 'Activation failed'
      disable_mega
      false
    end
  rescue JSON::ParserError
    Rails.logger.error 'Invalid response format from activation service'
    false
  end

  def disable_mega
    mega_license = InstallationConfig.find_by(name: 'INSTALLATION_MEGA')
    mega_license&.update(value: nil)

    Rails.logger.info 'Shutting down Puma workers...'
    begin
      redis = Redis.new(url: ENV.fetch('REDIS_URL', nil))
      redis.set('puma_shutdown', true)
    rescue Redis::BaseError => e
      Rails.logger.error "Failed to set shutdown flag in Redis: #{e.message}"
    end

    begin
      Rails.logger.info 'Initiating graceful shutdown sequence...'
      Sidekiq::CLI.instance.launcher.stop
    rescue StandardError => e
      Rails.logger.error "Error during shutdown sequence: #{e.message}"
    end
  end
end

Internal::CheckNewVersionsJob.prepend_mod_with('Internal::CheckNewVersionsJob')
