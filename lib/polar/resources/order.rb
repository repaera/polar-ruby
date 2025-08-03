# frozen_string_literal: true

module Polar
  module Resources
    class Order < Base
      def list(params = {})
        paginated_request("/v1/orders", params: params)
      end

      def retrieve(id)
        client.get("/v1/orders/#{id}")
      end

      def invoice(id)
        client.get("/v1/orders/#{id}/invoice")
      end

      def by_customer(customer_id, params = {})
        params[:customer_id] = customer_id
        list(params)
      end

      def by_subscription(subscription_id, params = {})
        params[:subscription_id] = subscription_id
        list(params)
      end
    end
  end
end