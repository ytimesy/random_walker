require "active_support/core_ext/integer/time"
require "securerandom"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.secret_key_base = ENV["SECRET_KEY_BASE"].presence || SecureRandom.hex(64)
  config.public_file_server.enabled = true
  config.assets.compile = true
  config.force_ssl = true
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }
  config.log_tags = [ :request_id ]
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.cache_store = :memory_store
  config.action_mailer.perform_caching = false
  config.i18n.fallbacks = true
  config.active_support.report_deprecations = false
end
