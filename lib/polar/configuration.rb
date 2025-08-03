# frozen_string_literal: true

module Polar
  class Configuration
    attr_accessor :access_token, :environment, :timeout, :retries

    API_ENDPOINTS = {
      sandbox: "https://sandbox-api.polar.sh",
      production: "https://api.polar.sh"
    }.freeze

    def initialize
      @environment = :sandbox
      @timeout = 30
      @retries = 3
    end

    def api_endpoint
      API_ENDPOINTS[@environment]
    end

    def headers
      {
        "Authorization" => "Bearer #{@access_token}",
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "User-Agent" => "polar-ruby/#{Polar::VERSION}"
      }
    end
  end
end