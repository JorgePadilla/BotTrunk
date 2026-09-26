# frozen_string_literal: true

module Ui
  # The bordered "nothing to show" box: an icon, a line, and whatever the
  # caller passes as a block for the way out of it.
  class EmptyStateComponent < ApplicationComponent
    def initialize(title:, icon: "search")
      @title = title
      @icon_name = icon
    end

    attr_reader :title
  end
end
