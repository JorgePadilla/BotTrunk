# frozen_string_literal: true

module Ui
  class NavbarComponentPreview < ViewComponent::Preview
    layout "component_preview"

    def default
      render Ui::NavbarComponent.new(active: "Catalog")
    end
  end
end
