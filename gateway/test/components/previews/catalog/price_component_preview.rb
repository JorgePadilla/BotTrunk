# frozen_string_literal: true

module Catalog
  class PriceComponentPreview < ViewComponent::Preview
    def default
      render Catalog::PriceComponent.new(amount: 0.005, suffix: "per call · 0.8 s")
    end

    def large
      render Catalog::PriceComponent.new(amount: 5.0, size: :lg, suffix: "USDC per call · p50 ~36 h")
    end
  end
end
