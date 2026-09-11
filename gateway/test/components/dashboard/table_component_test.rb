# frozen_string_literal: true

require "test_helper"

module Dashboard
  class TableComponentTest < ViewComponent::TestCase
    test "renders headers, rows and right-aligns numeric columns" do
      render_inline(TableComponent.new(columns: [ "Host", "Views" ], numeric: [ 1 ], rows: [ [ "discord.com", 12 ] ]))
      assert_selector "th", text: "Host"
      assert_selector "td.text-right", text: "12"
      assert_selector "td", text: "discord.com"
    end

    test "shows the empty message when there are no rows" do
      render_inline(TableComponent.new(columns: [ "A" ], rows: [], empty: "Quiet."))
      assert_text "Quiet."
      assert_no_selector "table"
    end
  end
end
