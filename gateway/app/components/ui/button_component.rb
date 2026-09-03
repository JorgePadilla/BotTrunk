# frozen_string_literal: true

module Ui
  # <%= render Ui::ButtonComponent.new(variant: :primary, icon: "plug") { "Connect agent" } %>
  # Renders an <a> when `href` is given, a <button> otherwise.
  class ButtonComponent < ApplicationComponent
    VARIANTS = { default: "btn", primary: "btn btn-primary", ghost: "btn btn-ghost", outline: "btn btn-outline" }.freeze
    SIZES    = { md: "", sm: "btn-sm", xs: "btn-xs", square: "btn-square" }.freeze

    def initialize(variant: :default, size: :md, href: nil, icon: nil, type: "button", **attrs)
      @variant = VARIANTS.fetch(variant)
      @size = SIZES.fetch(size)
      @href = href
      @icon = icon
      @type = type
      @attrs = attrs
    end

    def call
      content_tag(tag_name, **html_attrs) do
        safe_join([ (icon(@icon, class: "size-4") if @icon), content ].compact)
      end
    end

    private

    def tag_name = @href ? :a : :button

    def html_attrs
      base = { class: classes(@variant, @size, "font-medium", @attrs.delete(:class)) }
      base[@href ? :href : :type] = @href || @type
      base.merge(@attrs)
    end
  end
end
