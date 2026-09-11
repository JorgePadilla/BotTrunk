# frozen_string_literal: true

module Catalog
  # "$0.005" in mono with a muted suffix line ("per call · 0.8 s").
  class PriceComponent < ApplicationComponent
    SIZES = { md: "text-xl", lg: "text-4xl" }.freeze

    def initialize(amount:, suffix: "per call", size: :md)
      @amount = amount
      @suffix = suffix
      @size = SIZES.fetch(size)
    end

    def formatted
      # Show as many decimals as the price needs, at least 2 (0.005 → "0.005", 5.0 → "5.00").
      plain = @amount.is_a?(BigDecimal) ? @amount.to_s("F") : @amount.to_s
      decimals = [ 2, plain.split(".").last.to_s.sub(/0+\z/, "").length ].max
      "$#{format("%.#{decimals}f", @amount)}"
    end
  end
end
