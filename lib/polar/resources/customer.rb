# frozen_string_literal: true

module Polar
  module Resources
    class Customer < Base
      def list(params = {})
        paginated_request("/v1/customers", params: params)
      end

      def retrieve(id)
        client.get("/v1/customers/#{id}")
      end

      def create(params)
        client.post("/v1/customers", body: params)
      end

      def update(id, params)
        client.patch("/v1/customers/#{id}", body: params)
      end

      def delete(id)
        client.delete("/v1/customers/#{id}")
      end

      def lookup_by_email(email)
        list(email: email)
      end

      def lookup_by_external_id(external_id)
        list(external_id: external_id)
      end

      def portal_session(id, return_url: nil)
        body = {}
        body[:return_url] = return_url if return_url
        
        client.post("/v1/customers/#{id}/portal", body: body)
      end
    end
  end
end