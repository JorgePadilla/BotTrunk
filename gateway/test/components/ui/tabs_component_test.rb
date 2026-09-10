# frozen_string_literal: true

require "test_helper"

module Ui
  class TabsComponentTest < ViewComponent::TestCase
    test "labels only render without hrefs" do
      render_inline TabsComponent.new(tabs: %w[One Two], active: "Two")
      assert_selector "a[role=tab]", count: 2
      assert_selector "a[role=tab][aria-selected=true]", text: "Two"
      assert_no_selector "a[href]"
    end

    test "pairs render as links" do
      render_inline TabsComponent.new(tabs: [ [ "Overview", "#overview" ], [ "Call it", "#call" ] ], active: 1)
      assert_selector "a[href='#call'][aria-selected=true]", text: "Call it"
      assert_selector "a[href='#overview']", text: "Overview"
    end
  end
end
