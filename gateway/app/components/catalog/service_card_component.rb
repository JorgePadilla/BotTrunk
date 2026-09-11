# frozen_string_literal: true

module Catalog
  # One catalog entry: name, one-line summary, price and measured performance,
  # provider. A family (the deposit tiers) renders as a single card for the
  # cheapest variant, labelled with the range.
  class ServiceCardComponent < ApplicationComponent
    def initialize(service:, metrics: nil, variants: [])
      @service = service
      @metrics = metrics
      @variants = variants.size > 1 ? variants : []
    end

    attr_reader :service, :metrics

    def family? = @variants.any?

    def title = family? ? service.family_label : service.name

    def summary = family? ? service.family_summary : service.summary

    def badge
      return "On request" if service.on_request?

      nil
    end

    def price_prefix = family? ? "from" : nil

    def price_suffix
      return amount_range if family?

      [ "per call", metrics&.performance ].compact.join(" · ")
    end

    private

    def amount_range
      amounts = @variants.filter_map(&:price_hnl).sort
      return "#{@variants.size} options" if amounts.empty?

      "#{@variants.size} amounts · L#{number_with_delimiter(amounts.first)} – L#{number_with_delimiter(amounts.last)}"
    end

    def number_with_delimiter(n) = helpers.number_with_delimiter(n)
  end
end
