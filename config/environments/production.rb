require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Durable, process-shared cache so rate-limit counters and fragments survive
  # restarts and are consistent across Puma workers.
  config.cache_store = :solid_cache_store

  # Run Active Job on the database-backed Solid Queue backend so evaluator
  # pipelines execute in a worker process instead of holding a Puma thread.
  config.active_job.queue_adapter = :solid_queue

  # Allow the app's own origin(s) so the Turbo morph-refresh websocket connects
  # behind the SSL-terminating proxy. Set CABLE_ALLOWED_ORIGINS to a
  # comma-separated list of https origins (e.g. https://app.example.com).
  if ENV["CABLE_ALLOWED_ORIGINS"].present?
    config.action_cable.allowed_request_origins =
      ENV["CABLE_ALLOWED_ORIGINS"].split(",").map { |origin| origin.strip }
  end

  # Mail is not decoration here: a password reset and an email confirmation are
  # both delivered this way, and neither works without it. Configured from the
  # environment like every other outside service in this app (see
  # config/initializers/web_push.rb and anthropic.rb) rather than from
  # credentials, so a deploy can set it without re-encrypting anything.
  #
  # APP_HOST is what every link in an email is built from. There is no sensible
  # default — a reset link pointing at example.com is worse than no email — so
  # the boot check in config/initializers/mail.rb refuses to let it be guessed.
  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST", "example.com"),
    protocol: "https"
  }
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.perform_deliveries = ENV["SMTP_ADDRESS"].present?

  if ENV["SMTP_ADDRESS"].present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV.fetch("SMTP_ADDRESS"),
      port: ENV.fetch("SMTP_PORT", 587).to_i,
      user_name: ENV["SMTP_USER_NAME"],
      password: ENV["SMTP_PASSWORD"],
      authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain").to_sym,
      enable_starttls_auto: true
    }
  end

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
