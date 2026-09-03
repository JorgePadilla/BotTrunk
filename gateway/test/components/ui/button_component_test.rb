# frozen_string_literal: true

require "test_helper"

class Ui::ButtonComponentTest < ViewComponent::TestCase
  test "renders a button by default" do
    render_inline(Ui::ButtonComponent.new(variant: :primary)) { "Sign in" }
    assert_selector "button.btn.btn-primary[type=button]", text: "Sign in"
  end

  test "renders a link when href is given" do
    render_inline(Ui::ButtonComponent.new(href: "/sell")) { "Register" }
    assert_selector "a.btn[href='/sell']", text: "Register"
  end
end
