# frozen_string_literal: true

require "test_helper"

class ClientTest < Test::Unit::TestCase
  def setup
    super
    @client = Polar.client
  end

  test "handles successful response" do
    response_body = { "success" => true }
    
    stub_polar_request(:get, "/v1/test", response_body: response_body)
    
    result = @client.get("/v1/test")
    
    assert_equal true, result["success"]
  end

  test "handles 400 validation error" do
    error_response = { "error" => "Invalid parameters" }
    
    stub_polar_request(:get, "/v1/test", response_body: error_response, status: 400)
    
    assert_raises(Polar::ValidationError) do
      @client.get("/v1/test")
    end
  end

  test "handles 401 authentication error" do
    stub_polar_request(:get, "/v1/test", response_body: {}, status: 401)
    
    assert_raises(Polar::AuthenticationError) do
      @client.get("/v1/test")
    end
  end

  test "handles 403 authorization error" do
    stub_polar_request(:get, "/v1/test", response_body: {}, status: 403)
    
    assert_raises(Polar::AuthorizationError) do
      @client.get("/v1/test")
    end
  end

  test "handles 404 not found error" do
    stub_polar_request(:get, "/v1/test", response_body: {}, status: 404)
    
    assert_raises(Polar::NotFoundError) do
      @client.get("/v1/test")
    end
  end

  test "handles 429 rate limit error" do
    stub_polar_request(:get, "/v1/test", response_body: {}, status: 429)
    
    assert_raises(Polar::RateLimitError) do
      @client.get("/v1/test")
    end
  end

  test "handles 500 server error" do
    stub_polar_request(:get, "/v1/test", response_body: {}, status: 500)
    
    assert_raises(Polar::ServerError) do
      @client.get("/v1/test")
    end
  end

  test "includes correct headers" do
    stub_polar_request(:get, "/v1/test", response_body: {})
    
    @client.get("/v1/test")
    
    assert_requested :get, "https://sandbox-api.polar.sh/v1/test" do |req|
      req.headers["Authorization"] == "Bearer test_token_123" &&
      req.headers["Content-Type"] == "application/json" &&
      req.headers["Accept"] == "application/json" &&
      req.headers["User-Agent"] == "polar-ruby/#{Polar::VERSION}"
    end
  end

  test "resource accessors" do
    assert_instance_of Polar::Resources::Customer, @client.customers
    assert_instance_of Polar::Resources::Product, @client.products
    assert_instance_of Polar::Resources::Subscription, @client.subscriptions
    assert_instance_of Polar::Resources::Checkout, @client.checkouts
    assert_instance_of Polar::Resources::Order, @client.orders
    assert_instance_of Polar::Resources::Benefit, @client.benefits
  end
end