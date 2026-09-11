# frozen_string_literal: true

require "test_helper"

module Rates
  class UsdHnlTest < ActiveSupport::TestCase
    setup { @pinned = UsdHnl.stub_rate; UsdHnl.stub_rate = nil }
    teardown { UsdHnl.stub_rate = @pinned; ENV.delete("HNL_PER_USD") }

    test "a manual override wins" do
      ENV["HNL_PER_USD"] = "25.90"
      assert_equal BigDecimal("25.90"), UsdHnl.current
    end

    test "reads HNL from the feed" do
      stub_request(:get, UsdHnl::FEED).to_return(status: 200, body: { rates: { HNL: 26.31 } }.to_json, headers: { "Content-Type" => "application/json" })
      assert_equal BigDecimal("26.31"), UsdHnl.current
    end

    test "falls back when the feed is down or nonsense" do
      stub_request(:get, UsdHnl::FEED).to_return(status: 500, body: "")
      assert_equal UsdHnl::FALLBACK, UsdHnl.current

      stub_request(:get, UsdHnl::FEED).to_return(status: 200, body: { rates: {} }.to_json)
      assert_equal UsdHnl::FALLBACK, UsdHnl.current
    end
  end
end
