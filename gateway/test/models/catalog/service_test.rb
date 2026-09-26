# frozen_string_literal: true

require "test_helper"

class Catalog::ServiceTest < ActiveSupport::TestCase
  # /docs and /connect quote this figure when they explain the spending caps.
  # It was hard-coded at $414 and wrong within a week, so it comes from the
  # catalog now — and it has to mean *callable*, or the pages would tell people
  # to raise a cap for something nobody can buy.
  test "the quoted ceiling is the dearest thing an agent can actually call" do
    Catalog::Service.treat_all_live = false

    live = Catalog::Service.all.select(&:live?)
    on_request = Catalog::Service.all.reject(&:live?)
    assert on_request.any?, "the seed has on-request services to exclude"

    assert_equal live.map(&:price_atomic).max, Catalog::Service.top_live_price_atomic
    assert_operator Catalog::Service.top_live_price_atomic, :<, on_request.map(&:price_atomic).max
  ensure
    Catalog::Service.treat_all_live = true
  end
end
