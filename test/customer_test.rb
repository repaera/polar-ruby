# frozen_string_literal: true

require "test_helper"

class CustomerTest < Test::Unit::TestCase
  def setup
    super
    @client = Polar.client
  end

  test "list customers" do
    response_body = {
      "data" => [
        { "id" => "customer_123", "email" => "test@example.com" }
      ],
      "pagination" => { "total_count" => 1, "max_page" => 1 }
    }

    stub_polar_request(:get, "/v1/customers", response_body: response_body)
    
    result = @client.customers.list
    
    assert_equal 1, result[:data].length
    assert_equal "customer_123", result[:data].first["id"]
    assert_equal "test@example.com", result[:data].first["email"]
  end

  test "retrieve customer" do
    customer_data = { "id" => "customer_123", "email" => "test@example.com" }
    
    stub_polar_request(:get, "/v1/customers/customer_123", response_body: customer_data)
    
    result = @client.customers.retrieve("customer_123")
    
    assert_equal "customer_123", result["id"]
    assert_equal "test@example.com", result["email"]
  end

  test "create customer" do
    customer_params = { "email" => "new@example.com", "external_id" => "ext_123" }
    created_customer = { "id" => "customer_456", **customer_params }
    
    stub_polar_request(:post, "/v1/customers", response_body: created_customer)
    
    result = @client.customers.create(customer_params)
    
    assert_equal "customer_456", result["id"]
    assert_equal "new@example.com", result["email"]
  end

  test "update customer" do
    update_params = { "name" => "Updated Name" }
    updated_customer = { "id" => "customer_123", "name" => "Updated Name" }
    
    stub_polar_request(:patch, "/v1/customers/customer_123", response_body: updated_customer)
    
    result = @client.customers.update("customer_123", update_params)
    
    assert_equal "Updated Name", result["name"]
  end

  test "delete customer" do
    stub_polar_request(:delete, "/v1/customers/customer_123", response_body: {})
    
    result = @client.customers.delete("customer_123")
    
    assert_equal({}, result)
  end

  test "lookup by email" do
    response_body = {
      "data" => [{ "id" => "customer_123", "email" => "test@example.com" }]
    }
    
    stub_polar_request(:get, "/v1/customers?email=test%40example.com", response_body: response_body)
    
    result = @client.customers.lookup_by_email("test@example.com")
    
    assert_equal 1, result[:data].length
    assert_equal "test@example.com", result[:data].first["email"]
  end

  test "create portal session" do
    portal_data = { "url" => "https://portal.polar.sh/session_123" }
    
    stub_polar_request(:post, "/v1/customers/customer_123/portal", response_body: portal_data)
    
    result = @client.customers.portal_session("customer_123", return_url: "https://myapp.com/return")
    
    assert_equal "https://portal.polar.sh/session_123", result["url"]
  end
end