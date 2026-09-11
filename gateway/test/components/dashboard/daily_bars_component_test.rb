# frozen_string_literal: true

require "test_helper"

module Dashboard
  class DailyBarsComponentTest < ViewComponent::TestCase
    test "draws one bar per day scaled to the peak, and a zero bar is invisible" do
      series = [ [ Date.new(2026, 9, 9), 0 ], [ Date.new(2026, 9, 10), 2 ], [ Date.new(2026, 9, 11), 4 ] ]
      render_inline(DailyBarsComponent.new(series: series, label: "Views"))

      assert_selector "rect", count: 3
      assert_selector "rect[height='80']"
      assert_selector "rect[height='40']"
      assert_selector "rect[fill-opacity='0']"
      assert_text "6 · peak 4"
      assert_text "2026-09-09"
    end
  end
end
