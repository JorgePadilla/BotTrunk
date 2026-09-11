# frozen_string_literal: true

module Dashboard
  # A row of numbers with a label under each. `stats:` is an array of
  # { label:, value:, hint: } hashes; value is already formatted.
  class StatRowComponent < ApplicationComponent
    def initialize(stats:)
      @stats = stats
    end

    attr_reader :stats
  end
end
