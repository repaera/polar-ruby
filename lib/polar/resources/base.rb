# frozen_string_literal: true

module Polar
  module Resources
    class Base
      attr_reader :client

      def initialize(client)
        @client = client
      end

      protected

      def build_query_params(params)
        params.compact.transform_keys(&:to_s)
      end

      def format_datetime(datetime)
        return datetime if datetime.is_a?(String)
        datetime&.iso8601
      end

      def paginated_request(path, params: {})
        query_params = build_query_params(params)
        response = client.get(path, params: query_params)
        
        {
          data: response["data"] || [],
          pagination: response["pagination"] || {}
        }
      end
    end
  end
end