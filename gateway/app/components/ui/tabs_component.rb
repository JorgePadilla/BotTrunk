# frozen_string_literal: true

module Ui
  # Underline tabs. Pass `tabs:` as an array of labels; the active one is `active:` (index or label).
  # Purely presentational (links or Stimulus targets are the caller's job — see Docs::CodeSnippetComponent).
  class TabsComponent < ApplicationComponent
    def initialize(tabs:, active: 0, size: :md)
      @tabs = tabs
      @active = active.is_a?(Integer) ? tabs[active] : active
      @size = size
    end

    def active?(tab) = tab == @active

    def tab_classes(tab)
      classes("tab px-1 mr-5 font-medium",
              @size == :sm ? "text-[13px]" : "text-sm",
              active?(tab) ? "tab-active text-base-content" : "text-muted")
    end
  end
end
