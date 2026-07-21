source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Throttle abusive requests to public endpoints
gem "rack-attack", "~> 6.8"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Database-backed Active Job backend so evaluator pipelines run off the web thread [https://github.com/rails/solid_queue]
gem "solid_queue", "~> 1.1"
# Database-backed Action Cable backend so worker-issued Turbo broadcasts reach web clients [https://github.com/rails/solid_cable]
gem "solid_cable", "~> 4.0"
# Database-backed durable cache shared across processes (rate-limit counters, fragments) [https://github.com/rails/solid_cache]
gem "solid_cache", "~> 1.0"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Send Web Push notifications (daily check-in reminders) [https://github.com/pushpad/web-push]
gem "web-push", "~> 3.0"

# Official Anthropic SDK — powers the AI coach narrative that explains the
# auditable coaching-decision DAG in plain language [https://github.com/anthropics/anthropic-sdk-ruby]
gem "anthropic", "~> 1.9"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Stub and assert outbound HTTP requests in tests [https://github.com/bblimke/webmock]
  gem "webmock"
end
