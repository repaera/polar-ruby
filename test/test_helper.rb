# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "polar"

require "test-unit"
require "mocha/test_unit"
require "webmock/test_unit"

WebMock.disable_net_connect!(allow_localhost: true)

class Test::Unit::TestCase
  def setup
    Polar.reset_client!
    configure_polar_test
  end

  def teardown
    WebMock.reset!
  end

  private

  def configure_polar_test
    Polar.configure do |config|
      config.access_token = "test_token_123"
      config.environment = :sandbox
    end
  end

  def stub_polar_request(method, path, response_body: {}, status: 200)
    WebMock.stub_request(method, "https://sandbox-api.polar.sh#{path}")
           .to_return(
             status: status,
             body: response_body.to_json,
             headers: { "Content-Type" => "application/json" }
           )
  end
end
