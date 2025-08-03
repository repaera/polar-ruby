# frozen_string_literal: true

require "httparty"
require "active_support/core_ext/hash"
require "active_support/core_ext/string"

require_relative "polar/version"
require_relative "polar/configuration"
require_relative "polar/client"
require_relative "polar/error"
require_relative "polar/resources/base"
require_relative "polar/resources/customer"
require_relative "polar/resources/product"
require_relative "polar/resources/subscription"
require_relative "polar/resources/checkout"
require_relative "polar/resources/order"
require_relative "polar/resources/benefit"

module Polar
  class << self
    attr_accessor :configuration

    def configure
      self.configuration ||= Configuration.new
      yield(configuration)
    end

    def client
      @client ||= Client.new(configuration)
    end

    def reset_client!
      @client = nil
    end
  end
end
