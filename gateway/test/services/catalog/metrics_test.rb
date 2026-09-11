# frozen_string_literal: true

require "test_helper"

module Catalog
  class MetricsTest < ActiveSupport::TestCase
    def call_for(slug, amount: 90_000, latency: nil, status: 200, at: Time.current)
      Call.create!(service_slug: slug, pay_to: "G", network: "n", asset: "a", amount: amount,
                   commission: amount * 15 / 100, seller_amount: amount - (amount * 15 / 100),
                   upstream_status: status, upstream_latency_ms: latency, status: "settled", created_at: at)
    end

    test "a service with no calls reports nothing rather than a made-up number" do
      row = Metrics.for("scrape-markdown")
      assert_not row.any?
      assert_nil row.latency
      assert_nil row.success
      assert_nil row.reliability
      assert_equal 0, row.volume
    end

    test "median latency, success rate and volume come from the ledger" do
      call_for("scrape-markdown", latency: 400)
      call_for("scrape-markdown", latency: 800)
      call_for("scrape-markdown", latency: 1_200)
      call_for("scrape-markdown", latency: 5_000, status: 502)

      row = Metrics.for("scrape-markdown")
      assert_equal 4, row.calls
      assert_equal 1_000.0, row.p50_ms
      assert_equal "1.0 s", row.latency
      assert_equal "75%", row.success
      assert_equal "1 of 4 failed", row.reliability
      assert_equal 360_000, row.volume
    end

    test "a handful of calls reports counts, not a success percentage" do
      3.times { call_for("scrape-markdown", latency: 100) }
      row = Metrics.for("scrape-markdown")

      assert_equal "none failed yet", row.reliability
      assert_equal "100%", row.success
    end

    test "past the threshold it becomes a rate" do
      Metrics::MIN_FOR_RATE.times { call_for("scrape-markdown", latency: 100) }

      assert_equal "100% success", Metrics.for("scrape-markdown").reliability
    end

    test "latency under a second reads in milliseconds" do
      call_for("scrape-markdown", latency: 812)
      assert_equal "812 ms", Metrics.for("scrape-markdown").latency
      assert_equal "100%", Metrics.for("scrape-markdown").success
    end

    test "a family combines into one row weighted by calls" do
      call_for("deposit-bac-1000", amount: 42_510_122, latency: 100)
      call_for("deposit-bac-1000", amount: 42_510_122, latency: 300, status: 500)
      call_for("deposit-bac-10000", amount: 425_101_215, latency: 200)

      combined = Metrics.combined(%w[deposit-bac-1000 deposit-bac-2500 deposit-bac-10000])
      assert_equal 3, combined.calls
      assert_in_delta 0.667, combined.success_rate, 0.01
      assert_equal 510_121_459, combined.volume
      assert_equal 200.0, combined.p50_ms
    end

    test "totals add up across services and ignore the ones with no traffic" do
      call_for("scrape-markdown", latency: 100)
      call_for("page-metadata", amount: 20_000, latency: 50)

      totals = Metrics.totals
      assert_equal 2, totals.calls
      assert_equal 110_000, totals.volume
      assert_equal 2, totals.services
      assert totals.any?
    end
  end
end
