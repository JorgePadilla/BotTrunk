# frozen_string_literal: true

module Ui
  # Underline tabs. `tabs:` is an array of labels, or of [label, href] pairs
  # (anchors within the page, or real paths). `active:` is an index or a label.
  class TabsComponent < ApplicationComponent
    def initialize(tabs:, active: 0, size: :md)
      @tabs = tabs.map { |t| t.is_a?(Array) ? t : [ t, nil ] }
      @active = active.is_a?(Integer) ? @tabs[active]&.first : active
      @size = size
    end

    def tabs = @tabs

    def active?(label) = label == @active

    def tab_classes(label)
      classes("tab px-1 mr-5 font-medium",
              @size == :sm ? "text-[13px]" : "text-sm",
              active?(label) ? "tab-active text-base-content" : "text-muted hover:text-base-content")
    end
  end
end
