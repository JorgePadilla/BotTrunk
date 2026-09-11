# frozen_string_literal: true

module Catalog
  class PriceComponentPreview < ViewComponent::Preview
    def default
      render Catalog::PriceComponent.new(amount: 0.09, suffix: "per call · p50 812 ms · 100% success")
    end

    def large
      render Catalog::PriceComponent.new(amount: 5.0, size: :lg, suffix: "USDC per call · p50 ~36 h")
    end
  end
end
