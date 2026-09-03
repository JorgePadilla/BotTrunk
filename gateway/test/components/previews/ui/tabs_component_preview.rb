# frozen_string_literal: true

module Ui
  class TabsComponentPreview < ViewComponent::Preview
    def default
      render Ui::TabsComponent.new(tabs: [ "Overview", "Try it", "Schema", "Stats" ], active: "Overview")
    end
  end
end
