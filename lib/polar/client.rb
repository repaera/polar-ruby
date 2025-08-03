# frozen_string_literal: true

require "net/http"

module Polar
  class Client
    include HTTParty

    attr_reader :configuration

    def initialize(configuration)
      @configuration = configuration || Polar.configuration
      validate_configuration!
      
      self.class.base_uri(@configuration.api_endpoint)
      self.class.default_timeout(@configuration.timeout)
    end

    def get(path, params: {})
      request(:get, path, query: params)
    end

    def post(path, body: {})
      request(:post, path, body: body.to_json)
    end

    def put(path, body: {})
      request(:put, path, body: body.to_json)
    end

    def patch(path, body: {})
      request(:patch, path, body: body.to_json)
    end

    def delete(path)
      request(:delete, path)
    end

    def customers
      @customers ||= Resources::Customer.new(self)
    end

    def products
      @products ||= Resources::Product.new(self)
    end

    def subscriptions
      @subscriptions ||= Resources::Subscription.new(self)
    end

    def checkouts
      @checkouts ||= Resources::Checkout.new(self)
    end

    def orders
      @orders ||= Resources::Order.new(self)
    end

    def benefits
      @benefits ||= Resources::Benefit.new(self)
    end

    private

    def request(method, path, options = {})
      retries = 0
      begin
        response = self.class.send(method, path, {
          headers: @configuration.headers,
          **options
        })
        
        handle_response(response)
      rescue StandardError => e
        if e.class.name.include?("Timeout") || e.message.include?("timeout")
          retries += 1
          if retries <= @configuration.retries
            sleep(2 ** retries)
            retry
          else
            raise Polar::ServerError.new("Request timeout after #{@configuration.retries} retries")
          end
        else
          raise
        end
      end
    end

    def handle_response(response)
      case response.code
      when 200..299
        response.parsed_response
      when 400
        raise Polar::ValidationError.new(
          response.parsed_response["error"] || "Bad Request",
          status: response.code,
          response_body: response.parsed_response
        )
      when 401
        raise Polar::AuthenticationError.new(
          "Invalid or missing authentication credentials",
          status: response.code,
          response_body: response.parsed_response
        )
      when 403
        raise Polar::AuthorizationError.new(
          "Insufficient permissions",
          status: response.code,
          response_body: response.parsed_response
        )
      when 404
        raise Polar::NotFoundError.new(
          "Resource not found",
          status: response.code,
          response_body: response.parsed_response
        )
      when 429
        raise Polar::RateLimitError.new(
          "Rate limit exceeded",
          status: response.code,
          response_body: response.parsed_response
        )
      when 500..599
        raise Polar::ServerError.new(
          "Server error",
          status: response.code,
          response_body: response.parsed_response
        )
      else
        raise Polar::APIError.new(
          "Unexpected response code: #{response.code}",
          status: response.code,
          response_body: response.parsed_response
        )
      end
    end

    def validate_configuration!
      raise Polar::ConfigurationError.new("Access token is required") unless @configuration.access_token
      raise Polar::ConfigurationError.new("Invalid environment") unless @configuration.api_endpoint
    end
  end
end