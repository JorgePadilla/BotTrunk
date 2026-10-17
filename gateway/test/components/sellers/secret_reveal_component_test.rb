# frozen_string_literal: true

require "test_helper"

module Sellers
  class SecretRevealComponentTest < ViewComponent::TestCase
    test "the secret starts masked, can be shown and copied, and can be rotated" do
      render_inline(SecretRevealComponent.new(secret: "bts_abcdefghSECRETPART", rotate_url: "/seller/secret"))
      assert_selector "summary span", text: "bts_abcd••••••••••••••••"
      assert_selector "[data-clipboard-text-value='bts_abcdefghSECRETPART']"
      assert_selector "form[action='/seller/secret'] button", text: "Rotate secret"
    end
  end
end
