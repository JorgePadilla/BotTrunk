# frozen_string_literal: true

module Ui
  # Small rounded label. Tone :neutral (default) or :success (paid / verified / settled).
  class PillComponent < ApplicationComponent
    TONES = { neutral: "badge badge-outline text-muted", success: "badge badge-outline text-success border-success/40" }.freeze

    def initialize(tone: :neutral, icon: nil)
      @tone = TONES.fetch(tone)
      @icon = icon
    end

    def call
      content_tag(:span, class: classes(@tone, "gap-1.5 font-medium text-xs h-6")) do
        safe_join([ (icon(@icon, class: "size-3.5") if @icon), content ].compact)
      end
    end
  end
end
