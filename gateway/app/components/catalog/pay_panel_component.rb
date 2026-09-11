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

    def price_suffix
      parts = [ "USDC per call" ]
      parts << metrics.performance if metrics&.any?
      parts << "measured over #{metrics.calls} #{'call'.pluralize(metrics.calls)}" if metrics&.any?
      parts.compact.join(" · ")
    end

    def facts
      rows = [ [ "Network", service.network ], [ "Asset", service.asset ], [ "Facilitator", service.facilitator ], [ "Provider", service.provider.delete_prefix("By ") ] ]
      rows << [ "Priced in", "L#{helpers.number_with_delimiter(service.price_hnl)} at today's rate" ] if service.lempira?
      rows << [ "Paid calls", metrics.calls.to_s ] if metrics&.any?
      rows
    end

    def request_link = "mailto:#{SUPPORT_EMAIL}?subject=#{ERB::Util.url_encode("Request access: #{service.name}")}"
  end
end
