# frozen_string_literal: true

module Polar
  class Error < StandardError; end
  
  class APIError < Error
    attr_reader :status, :response_body, :error_code

    def initialize(message, status: nil, response_body: nil, error_code: nil)
      super(message)
      @status = status
      @response_body = response_body
      @error_code = error_code
    end
  end

  class AuthenticationError < APIError; end
  class AuthorizationError < APIError; end
  class NotFoundError < APIError; end
  class ValidationError < APIError; end
  class RateLimitError < APIError; end
  class ServerError < APIError; end
  class ConfigurationError < Error; end
end