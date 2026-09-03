# frozen_string_literal: true

module Catalog
  # Right rail of the service page: big price, payment facts, and the test-call CTA.
  class PayPanelComponent < ApplicationComponent
    def initialize(service:)
      @service = service
    end

    attr_reader :service

    def facts
      [ [ "Network", service.network ], [ "Asset", service.asset ], [ "Facilitator", service.facilitator ], [ "Provider", service.provider.delete_prefix("By ") ] ]
    end
  end
end
