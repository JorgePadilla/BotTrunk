# frozen_string_literal: true

module Payments
  # Payment adapters: the only code that knows about chains and facilitators.
  module Adapters
    # Tests swap the adapter here (see test/support); production uses config.
    mattr_accessor :stubs_current, instance_accessor: false

    def self.current
      stubs_current || Rails.configuration.x402.adapter.constantize.new
    end
  end
end
