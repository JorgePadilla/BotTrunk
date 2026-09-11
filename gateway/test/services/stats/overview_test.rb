# frozen_string_literal: true

require "test_helper"

module Stats
  class OverviewTest < ActiveSupport::TestCase
    setup do
      @now = Time.utc(2026, 9, 11, 12)
      track("page_view", path: "/docs", referrer: "https://discord.com/x", ua: "Mozilla/5.0 Chrome", ip: "1.1.1.1", at: @now - 1.hour)
      track("page_view", path: "/", referrer: "https://discord.com/y", ua: "Mozilla/5.0 Chrome", ip: "1.1.1.1", at: @now - 2.hours)
      track("page_view", path: "/", ua: "Mozilla/5.0 Firefox", ip: "2.2.2.2", at: @now - 3.days)
      track("payment_required", slug: "scrape-markdown", ua: "bottrunk-mcp/0.1.0", ip: "3.3.3.3", at: @now - 10.minutes)
      track("payment_rejected", slug: "scrape-markdown", ua: "curl/8", ip: "4.4.4.4", at: @now - 40.days)
      Call.create!(service_slug: "scrape-markdown", pay_to: "GATEWAY", network: "algorand:x", asset: "31566704", amount: 5000,
                   commission: 750, seller_amount: 4250, payer_address: "PAYER-A", transaction_id: "T1", status: "settled", created_at: @now - 5.minutes)
      Call.create!(service_slug: "scrape-markdown", pay_to: "GATEWAY", network: "algorand:x", asset: "31566704", amount: 5000,
                   commission: 750, seller_amount: 4250, payer_address: "PAYER-A", transaction_id: "T2", status: "settled", created_at: @now - 2.days)
    end

    test "windows count views, visitors, probes, settled calls, payers and money" do
      report = Overview.new(days: 30, now: @now).call[:report]
      today = report.windows.find { |w| w.label == "24 hours" }
      assert_equal 2, today.page_views
      assert_equal 1, today.visitors
      assert_equal 1, today.probes
      assert_equal 1, today.settled
      assert_equal 5000, today.volume
      assert_equal 750, today.commission

      week = report.windows.find { |w| w.label == "7 days" }
      assert_equal 3, week.page_views
      assert_equal 2, week.visitors
      assert_equal 2, week.settled
      assert_equal 1, week.payers
      assert_equal 10_000, week.volume

      all = report.windows.find { |w| w.label == "All time" }
      assert_equal 1, all.rejected
    end

    test "daily series has one entry per day ending today" do
      report = Overview.new(days: 7, now: @now).call[:report]
      assert_equal 7, report.days.size
      assert_equal @now.to_date, report.days.last.date
      assert_equal 2, report.days.last.page_views
      assert_equal 1, report.days.last.settled
      assert_equal 1, report.days[-4].page_views # the Firefox view, 3 days ago
      assert_equal 1, report.days[-3].settled    # T2, 2 days ago
    end

    test "per-service rows, referrers, pages and clients" do
      report = Overview.new(days: 30, now: @now).call[:report]
      scrape = report.services.find { |s| s.slug == "scrape-markdown" }
      assert_equal 1, scrape.probes
      assert_equal 0, scrape.rejected # the rejection is 40 days old
      assert_equal 2, scrape.settled
      assert_equal 10_000, scrape.volume
      assert_equal Catalog::Service.all.size, report.services.size
      assert_equal [ [ "discord.com", 2 ] ], report.referrers
      assert_equal [ "/", "/docs" ], report.pages.map(&:first).sort
      assert_equal [ [ "bottrunk-mcp", 1 ] ], report.clients
      assert_equal %w[T1 T2], report.recent_calls.map(&:transaction_id)
    end

    private

    def track(name, path: "/s/x", referrer: nil, ua: nil, ip: nil, slug: nil, at: @now)
      Analytics::Track.new(name: name, path: path, referrer: referrer, user_agent: ua, ip: ip, service_slug: slug, now: at).call.tap do |r|
        raise r.error unless r.success?
      end
    end
  end
end
