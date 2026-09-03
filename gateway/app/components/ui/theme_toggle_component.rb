# frozen_string_literal: true

module Ui
  # Sun/moon button bound to the `theme` Stimulus controller on <html>.
  class ThemeToggleComponent < ApplicationComponent
    def call
      content_tag(:button, type: "button", class: "btn btn-ghost btn-sm btn-square text-muted", "aria-label": "Toggle theme",
                  data: { action: "theme#toggle" }) do
        safe_join([ icon("sun", class: "size-4 hidden [[data-theme=bottrunk-dark]_&]:block"),
                    icon("moon", class: "size-4 block [[data-theme=bottrunk-dark]_&]:hidden") ])
      end
    end
  end
end
