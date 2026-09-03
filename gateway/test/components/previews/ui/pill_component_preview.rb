# frozen_string_literal: true

module Ui
  class PillComponentPreview < ViewComponent::Preview
    def neutral
      render(Ui::PillComponent.new) { "Human-fulfilled" }
    end

    def success
      render(Ui::PillComponent.new(tone: :success, icon: "check")) { "Verified" }
    end
  end
end
