# frozen_string_literal: true

module Ui
  class EmptyStateComponentPreview < ViewComponent::Preview
    def default
      render(Ui::EmptyStateComponent.new(title: "Nothing here yet.")) do
        "No service matches."
      end
    end

    def without_a_body
      render Ui::EmptyStateComponent.new(title: "No orders in the queue.", icon: "inbox")
    end
  end
end
