# frozen_string_literal: true

module Catalog
  class PayPanelComponentPreview < ViewComponent::Preview
    def default
      render_with_template(locals: { service: Catalog::Service.find("scrape-markdown") })
    end
  end
end
