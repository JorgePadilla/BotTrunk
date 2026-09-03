# frozen_string_literal: true

module Catalog
  class FilterChipsComponentPreview < ViewComponent::Preview
    def default
      render Catalog::FilterChipsComponent.new(categories: Catalog::Service.categories, active: "Data")
    end
  end
end
