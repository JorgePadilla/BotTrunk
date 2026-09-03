# frozen_string_literal: true

require "test_helper"

class Gateway::CallTimelineComponentTest < ViewComponent::TestCase
  test "renders one item per step with its state" do
    render_inline(Gateway::CallTimelineComponent.new(steps: [
      { title: "402 Payment Required" },
      { title: "Upstream call", state: :pending }
    ]))
    assert_selector "li", count: 2
    assert_selector "li span.text-success", count: 1
    assert_selector "li span.text-muted", count: 1
  end
end
