# frozen_string_literal: true

require "test_helper"

class CheckoutTest < Test::Unit::TestCase
  def setup
    super
    @client = Polar.client
  end

  test "create checkout" do
    checkout_params = {
      "product_id" => "product_123",
      "success_url" => "https://myapp.com/success",
      "cancel_url" => "https://myapp.com/cancel"
    }
    created_checkout = { 
      "id" => "checkout_456", 
      "url" => "https://polar.sh/checkout/checkout_456",
      **checkout_params 
    }
    
    stub_polar_request(:post, "/v1/checkouts", response_body: created_checkout)
    
    result = @client.checkouts.create(checkout_params)
    
    assert_equal "checkout_456", result["id"]
    assert_equal "https://polar.sh/checkout/checkout_456", result["url"]
    assert_equal "product_123", result["product_id"]
  end

  test "create custom checkout" do
    checkout_params = { "product_id" => "product_123" }
    created_checkout = { "id" => "checkout_456", **checkout_params }
    
    stub_polar_request(:post, "/v1/checkouts", response_body: created_checkout)
    
    result = @client.checkouts.create_custom(checkout_params)
    
    assert_equal "checkout_456", result["id"]
  end

  test "create custom checkout validates required fields" do
    assert_raises(Polar::ValidationError) do
      @client.checkouts.create_custom({})
    end
  end

  test "retrieve checkout" do
    checkout_data = { "id" => "checkout_123", "status" => "active" }
    
    stub_polar_request(:get, "/v1/checkouts/checkout_123", response_body: checkout_data)
    
    result = @client.checkouts.retrieve("checkout_123")
    
    assert_equal "checkout_123", result["id"]
    assert_equal "active", result["status"]
  end

  test "expire checkout" do
    expired_checkout = { "id" => "checkout_123", "status" => "expired" }
    
    stub_polar_request(:post, "/v1/checkouts/checkout_123/expire", response_body: expired_checkout)
    
    result = @client.checkouts.expire("checkout_123")
    
    assert_equal "expired", result["status"]
  end

  test "create subscription tier upgrade" do
    upgrade_params = {
      customer_id: "customer_123",
      subscription_id: "sub_123", 
      subscription_tier_id: "tier_456"
    }
    created_checkout = { "id" => "checkout_789", **upgrade_params.stringify_keys }
    
    stub_polar_request(:post, "/v1/checkouts", response_body: created_checkout)
    
    result = @client.checkouts.create_subscription_tier_upgrade(**upgrade_params)
    
    assert_equal "checkout_789", result["id"]
    assert_equal "customer_123", result["customer_id"]
  end
end