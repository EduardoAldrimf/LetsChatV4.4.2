require Rails.root.join('lib/redis/config')

schedule_file = 'config/schedule.yml'

Sidekiq.configure_client do |config|
  config.redis = Redis::Config.app
end

Sidekiq.configure_server do |config|
  config.redis = Redis::Config.app

  # skip the default start stop logging
  if Rails.env.production?
    config.logger.formatter = Sidekiq::Logger::Formatters::JSON.new
    config[:skip_default_job_logging] = true
    config.logger.level = Logger.const_get(ENV.fetch('LOG_LEVEL', 'info').upcase.to_s)
  end
end

# Función segura para detectar si estamos precompilando assets
def precompiling_assets?
  # ARGV estará disponible y contiene 'assets:precompile' durante la compilación
  defined?(Rails::Server).nil? && ARGV.any? { |arg| arg.include?('assets:precompile') }
end

# https://github.com/ondrejbartas/sidekiq-cron
unless precompiling_assets?
  Rails.application.reloader.to_prepare do
    if File.exist?(schedule_file) && Sidekiq.server?
      Sidekiq::Cron::Job.load_from_hash YAML.load_file(schedule_file)

      ['internal_check_new_versions_job'].each do |job_name|
        job = Sidekiq::Cron::Job.find(job_name)
        if job && job.status != 'enabled'
          job.enable!
          Rails.logger.debug { "Job #{job} has been enabled." }
        end

        job_class_name = job.klass
        job_class = job_class_name.constantize
        job_class.perform_later
        Rails.logger.debug { "Enqueued #{job_class_name} to run on startup." }
      end
    end
  end
end