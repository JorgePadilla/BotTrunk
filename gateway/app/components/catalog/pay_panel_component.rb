# frozen_string_literal: true

module Catalog
  # Right rail of the service page: the price, the payment facts, the other
  # amounts when the service is one of a family, and the call to action.
  class PayPanelComponent < ApplicationComponent
    SUPPORT_EMAIL = "hello@bottrunk.com"

    def initialize(service:, metrics: nil, variants: [])
      @service = service
      @metrics = metrics
      @variants = variants.size > 1 ? variants.sort_by(&:price_atomic) : []
    end

    attr_reader :service, :metrics

    def family? = @variants.any?

    def variants = @variants

    # The price line stays a price line. Measured numbers go in the facts
    # below it, where there is room to say what they actually measure —
    # "p50 38 ms" next to a price invites an agent to budget a 38 ms timeout
    # for a call that takes four seconds to settle.
    def price_suffix = "USDC per call"

    def facts
      rows = [ [ "Network", service.network ], [ "Asset", service.asset ], [ "Facilitator", service.facilitator ], [ "Provider", service.provider.delete_prefix("By ") ] ]
      rows << [ "Priced in", "L#{helpers.number_with_delimiter(service.price_hnl)} at today's rate" ] if service.lempira?
      return rows unless metrics&.any?

      rows << [ "Paid calls", metrics.calls.to_s ]
      rows << [ "Fulfilment", "p50 #{metrics.latency}, settlement extra" ] if metrics.latency
      rows << [ "Reliability", metrics.reliability ] if metrics.reliability
      rows
    end

    def request_link = "mailto:#{SUPPORT_EMAIL}?subject=#{ERB::Util.url_encode("Request access: #{service.name}")}"
  end
end
