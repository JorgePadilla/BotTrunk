# frozen_string_literal: true

module Ui
  # Hairline-bordered container. Padding is generous on purpose (see the mockups).
  class CardComponent < ApplicationComponent
    def initialize(padding: "p-7", href: nil, **attrs)
      @padding = padding
      @href = href
      @attrs = attrs
    end

    def call
      klass = classes("card bg-base-100 border hairline rounded-box", @padding,
                      @href && "transition-colors hover:border-base-content/30", @attrs.delete(:class))
      if @href
        link_to(@href, class: klass, **@attrs) { content }
      else
        content_tag(:div, class: klass, **@attrs) { content }
      end
    end
  end
end
