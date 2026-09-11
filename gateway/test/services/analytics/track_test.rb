# frozen_string_literal: true

require "test_helper"

module Analytics
  class TrackTest < ActiveSupport::TestCase
    test "records an event with a daily visitor hash, referrer host and client, but no IP or UA" do
      result = Track.new(name: "page_view", path: "/docs", referrer: "https://www.reddit.com/r/AI_Agents/x",
                         user_agent: "Mozilla/5.0 Chrome/128", ip: "203.0.113.9").call

      assert result.success?
      event = result[:event]
      assert_equal "page_view", event.name
      assert_equal "reddit.com", event.referrer_host
      assert_equal "browser", event.client
      assert_equal 16, event.visitor.length
      assert_not_includes event.attributes.values.map(&:to_s), "203.0.113.9"
      assert_not_includes event.attributes.values.map(&:to_s), "Mozilla/5.0 Chrome/128"
    end

    test "the same visitor hashes the same within a day and differently the next day" do
      today = Time.utc(2026, 9, 11, 10)
      a = Track.new(name: "page_view", user_agent: "curl/8.0", ip: "198.51.100.1", now: today).call[:event]
      b = Track.new(name: "page_view", user_agent: "curl/8.0", ip: "198.51.100.1", now: today + 1.hour).call[:event]
      c = Track.new(name: "page_view", user_agent: "curl/8.0", ip: "198.51.100.1", now: today + 1.day).call[:event]
      assert_equal a.visitor, b.visitor
      assert_not_equal a.visitor, c.visitor
    end

    test "classifies user agents coarsely" do
      assert_equal "bottrunk-mcp", Track.classify("bottrunk-mcp/0.1.0 node")
      assert_equal "x402-client", Track.classify("x402-fetch/2.6.1")
      assert_equal "curl", Track.classify("curl/8.4.0")
      assert_equal "python", Track.classify("python-requests/2.32")
      assert_equal "node", Track.classify("undici")
      assert_equal "bot", Track.classify("Mozilla/5.0 (compatible; Googlebot/2.1)")
      assert_equal "browser", Track.classify("Mozilla/5.0 (Macintosh) AppleWebKit Safari/605")
      assert_equal "other", Track.classify(nil)
    end

    test "never raises: an invalid event becomes a failure result" do
      result = Track.new(name: "not-a-real-event").call
      assert result.failure?
      assert_equal :analytics_error, result.code
      assert_equal 0, Event.count
    end
  end
end
