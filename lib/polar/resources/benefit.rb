# frozen_string_literal: true

module Polar
  module Resources
    class Benefit < Base
      def list(params = {})
        paginated_request("/v1/benefits", params: params)
      end

      def retrieve(id)
        client.get("/v1/benefits/#{id}")
      end

      def create(params)
        client.post("/v1/benefits", body: params)
      end

      def update(id, params)
        client.patch("/v1/benefits/#{id}", body: params)
      end

      def delete(id)
        client.delete("/v1/benefits/#{id}")
      end

      def grants(benefit_id, params = {})
        paginated_request("/v1/benefits/#{benefit_id}/grants", params: params)
      end

      def grant(benefit_id, customer_id:, **options)
        client.post("/v1/benefits/#{benefit_id}/grants", body: {
          customer_id: customer_id,
          **options
        })
      end

      def revoke_grant(benefit_id, grant_id)
        client.delete("/v1/benefits/#{benefit_id}/grants/#{grant_id}")
      end
    end
  end
end