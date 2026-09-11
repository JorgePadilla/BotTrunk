# frozen_string_literal: true

module Catalog
  class ServiceCardComponentPreview < ViewComponent::Preview
    def default
      render_with_template(locals: { service: Catalog::Service.find("scrape-markdown") })
    end

    def human_fulfilled
      render_with_template(template: "catalog/service_card_component_preview/default",
                           locals: { service: Catalog::Service.find("verify-business-hn") })
    end

    def family
      tiers = Catalog::Service.find("deposit-bac-1000").variants
      render(Catalog::ServiceCardComponent.new(service: tiers.first, variants: tiers))
    end

    def grid
      render_with_template(locals: { services: Catalog::Service.all })
    end
  end
end
