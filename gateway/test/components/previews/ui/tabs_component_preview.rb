# frozen_string_literal: true

module Ui
  class TabsComponentPreview < ViewComponent::Preview
    def default
      render Ui::TabsComponent.new(tabs: [ [ "Overview", "#overview" ], [ "Call it", "#call" ], [ "Input", "#input" ], [ "Output", "#output" ] ], active: "Overview")
    end
  end
end
