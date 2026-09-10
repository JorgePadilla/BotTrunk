# frozen_string_literal: true

module Ui
  # Search field with the ⌘K hint. Submits as GET `?q=` to `action` (the catalog);
  # the search Stimulus controller handles ⌘K focus and Esc.
  class SearchInputComponent < ApplicationComponent
    def initialize(placeholder: "Search services", name: "q", value: nil, width: "w-64", size: :sm, action: "/")
      @placeholder = placeholder
      @name = name
      @value = value
      @width = width
      @size = size
      @action = action
    end
  end
end
