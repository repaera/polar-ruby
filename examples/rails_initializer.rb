# frozen_string_literal: true
# config/initializers/polar.rb

Polar.configure do |config|
  config.access_token = Rails.application.credentials.polar[:access_token]
  config.environment = Rails.env.production? ? :production : :sandbox
  config.timeout = 30
  config.retries = 3
end