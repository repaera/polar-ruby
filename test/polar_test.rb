# frozen_string_literal: true

require "test_helper"

class PolarTest < Test::Unit::TestCase
  test "VERSION" do
    assert do
      ::Polar.const_defined?(:VERSION)
    end
  end

  test "configuration" do
    Polar.configure do |config|
      config.access_token = "test_token"
      config.environment = :production
      config.timeout = 60
    end

    assert_equal "test_token", Polar.configuration.access_token
    assert_equal :production, Polar.configuration.environment
    assert_equal 60, Polar.configuration.timeout
    assert_equal "https://api.polar.sh", Polar.configuration.api_endpoint
  end

  test "client initialization" do
    client = Polar.client
    assert_instance_of Polar::Client, client
    assert_equal Polar.configuration, client.configuration
  end

  test "reset client" do
    original_client = Polar.client
    Polar.reset_client!
    new_client = Polar.client
    
    refute_same original_client, new_client
  end

  test "configuration error without access token" do
    Polar.configure do |config|
      config.access_token = nil
    end

    assert_raises(Polar::ConfigurationError) do
      Polar::Client.new(Polar.configuration)
    end
  end
end
