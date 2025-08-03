# frozen_string_literal: true

module Polar
  module Resources
    class Checkout < Base
      def list(params = {})
        paginated_request("/v1/checkouts", params: params)
      end

      def retrieve(id)
        client.get("/v1/checkouts/#{id}")
      end

      def create(params)
        client.post("/v1/checkouts", body: params)
      end

      def update(id, params)
        client.patch("/v1/checkouts/#{id}", body: params)
      end

      def create_custom(params)
        required_fields = [:product_id]
        validate_required_fields(params, required_fields)
        
        create(params)
      end

      def create_subscription_tier_upgrade(customer_id:, subscription_id:, subscription_tier_id:, **options)
        create({
          customer_id: customer_id,
          subscription_id: subscription_id,
          subscription_tier_id: subscription_tier_id,
          **options
        })
      end

      def expire(id)
        client.post("/v1/checkouts/#{id}/expire")
      end

      private

      def validate_required_fields(params, required_fields)
        param_keys = params.keys.map(&:to_sym)
        missing_fields = required_fields - param_keys
        if missing_fields.any?
          raise Polar::ValidationError.new("Missing required fields: #{missing_fields.join(', ')}")
        end
      end
    end
  end
end