# frozen_string_literal: true

module Ui
  class ButtonComponentPreview < ViewComponent::Preview
    # @param variant select { choices: [default, primary, ghost, outline] }
    # @param size select { choices: [md, sm, xs] }
    def default(variant: :default, size: :md)
      render(Ui::ButtonComponent.new(variant: variant.to_sym, size: size.to_sym)) { "Register a service" }
    end

    def with_icon
      render(Ui::ButtonComponent.new(variant: :primary, icon: "zap")) { "Run a paid test call" }
    end

    def as_link
      render(Ui::ButtonComponent.new(href: "/", icon: "arrow-right")) { "Register a service" }
    end
  end
end
