# frozen_string_literal: true

module Docs
  class SchemaTableComponentPreview < ViewComponent::Preview
    def default
      render Docs::SchemaTableComponent.new(fields: Catalog::Service.find("scrape-markdown").inputs)
    end
  end
end
