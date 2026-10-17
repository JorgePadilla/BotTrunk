# frozen_string_literal: true

module Sellers
  class SecretRevealComponentPreview < ViewComponent::Preview
    def default
      render SecretRevealComponent.new(secret: "bts_7Kq2mWfE9xP4rT1yB8nC3vL6hJ5dG0sA2zQwXe", rotate_url: "#")
    end
  end
end
