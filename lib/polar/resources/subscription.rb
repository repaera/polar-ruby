# frozen_string_literal: true

module Polar
  module Resources
    class Subscription < Base
      def list(params = {})
        paginated_request("/v1/subscriptions", params: params)
      end

      def retrieve(id)
        client.get("/v1/subscriptions/#{id}")
      end

      def create(params)
        client.post("/v1/subscriptions", body: params)
      end

      def update(id, params)
        client.patch("/v1/subscriptions/#{id}", body: params)
      end

      def cancel(id, cancel_at_period_end: true)
        client.post("/v1/subscriptions/#{id}/cancel", body: {
          cancel_at_period_end: cancel_at_period_end
        })
      end

      def reactivate(id)
        client.post("/v1/subscriptions/#{id}/reactivate")
      end

      def change_product(id, product_id, price_id: nil)
        body = { product_id: product_id }
        body[:price_id] = price_id if price_id
        
        client.post("/v1/subscriptions/#{id}/change", body: body)
      end

      def export_benefits(id, params = {})
        query_params = build_query_params(params)
        client.get("/v1/subscriptions/#{id}/benefits", params: query_params)
      end
    end
  end
end