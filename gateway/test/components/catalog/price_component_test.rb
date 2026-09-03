# frozen_string_literal: true

require "test_helper"

class Catalog::PriceComponentTest < ViewComponent::TestCase
  test "keeps sub-cent precision and pads whole numbers" do
    assert_equal "$0.005", Catalog::PriceComponent.new(amount: 0.005).formatted
    assert_equal "$5.00", Catalog::PriceComponent.new(amount: 5.0).formatted
    assert_equal "$0.50", Catalog::PriceComponent.new(amount: 0.5).formatted
  end
end
