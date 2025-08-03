# frozen_string_literal: true

module Polar
  module Resources
    class Product < Base
      def list(params = {})
        paginated_request("/v1/products", params: params)
      end

      def retrieve(id)
        client.get("/v1/products/#{id}")
      end

      def create(params)
        client.post("/v1/products", body: params)
      end

      def update(id, params)
        client.patch("/v1/products/#{id}", body: params)
      end

      def benefits(id, params = {})
        paginated_request("/v1/products/#{id}/benefits", params: params)
      end

      def update_benefits(id, benefits)
        client.post("/v1/products/#{id}/benefits", body: { benefits: benefits })
      end
    end
  end
end