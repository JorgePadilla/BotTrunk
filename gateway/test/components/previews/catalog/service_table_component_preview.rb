# frozen_string_literal: true

module Catalog
  class ServiceTableComponentPreview < ViewComponent::Preview
    def default
      render Catalog::ServiceTableComponent.new(services: Catalog::Ranking.new.services)
    end

    # With `path:`, the price header becomes a sort toggle.
    def sortable
      render Catalog::ServiceTableComponent.new(services: Catalog::Ranking.new.by_price, path: "/services", sort: "price")
    end

    def one_category
      render Catalog::ServiceTableComponent.new(services: Catalog::Service.all.select { |s| s.category == "Payments" })
    end
  end
end
