# frozen_string_literal: true

module Ui
  class SearchInputComponentPreview < ViewComponent::Preview
    def default
      render Ui::SearchInputComponent.new
    end
  end
end
