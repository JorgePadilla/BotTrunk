# frozen_string_literal: true

module Catalog
  # "$0.09" in mono with an optional "from" prefix and a muted suffix line
  # ("per call · p50 812 ms").
  class PriceComponent < ApplicationComponent
    SIZES = { md: "text-xl", lg: "text-4xl" }.freeze

    def initialize(amount:, suffix: "per call", size: :md, prefix: nil)
      @amount = amount
      @suffix = suffix
      @size = SIZES.fetch(size)
      @prefix = prefix
    end

    attr_reader :prefix

    def formatted
      # Show as many decimals as the price needs, at least 2 (0.005 → "0.005", 5.0 → "5.00").
      plain = @amount.is_a?(BigDecimal) ? @amount.to_s("F") : @amount.to_s
      decimals = @amount >= 1 ? 2 : [ 2, plain.split(".").last.to_s.sub(/0+\z/, "").length ].max
      "$#{format("%.#{decimals}f", @amount)}"
    end
  end
end
