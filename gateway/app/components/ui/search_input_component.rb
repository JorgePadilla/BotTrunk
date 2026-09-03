# frozen_string_literal: true

module Ui
  # Search field with the ⌘K hint. Wire the real command palette later (Stimulus).
  class SearchInputComponent < ApplicationComponent
    def initialize(placeholder: "Search", name: "q", value: nil, width: "w-64", size: :sm)
      @placeholder = placeholder
      @name = name
      @value = value
      @width = width
      @size = size
    end
  end
end
