# frozen_string_literal: true

require "test_helper"

module Fulfillers
  class UrlHealthTest < ActiveSupport::TestCase
    setup do
      UrlHealth.tls_prober = ->(host, _port) { { issuer: "Let's Encrypt", expires_at: "2026-12-01T00:00:00Z", days_left: 80, host: host } }
    end

    teardown { UrlHealth.tls_prober = nil }

    test "follows the redirect chain and reports the final status, headers and certificate" do
      stub_request(:get, "https://example.com/start").to_return(status: 301, headers: { "Location" => "https://example.com/end" })
      stub_request(:get, "https://example.com/end").to_return(status: 200, headers: { "Content-Type" => "text/html", "Server" => "nginx" }, body: "hi")

      result = UrlHealth.new(input: { "url" => "https://example.com/start" }).call
      assert result.success?
      out = JSON.parse(result[:body])

      assert_equal true, out["ok"]
      assert_equal 200, out["status"]
      assert_equal "https://example.com/end", out["final_url"]
      assert_equal 1, out["redirects"]
      assert_equal [ 301, 200 ], out["chain"].map { |h| h["status"] }
      assert_equal "nginx", out.dig("headers", "server")
      assert_equal 80, out.dig("tls", "days_left")
      assert_equal "Let's Encrypt", out.dig("tls", "issuer")
    end

    test "a dead site is reported, not refused" do
      stub_request(:get, "https://example.com/down").to_return(status: 503)
      out = JSON.parse(UrlHealth.new(input: { "url" => "https://example.com/down" }).call[:body])
      assert_equal false, out["ok"]
      assert_equal 503, out["status"]
      assert_nil out["chain"], "a single hop needs no chain"
    end

    test "http URLs have no TLS block and connection errors answer without failing" do
      stub_request(:get, "http://example.com/plain").to_return(status: 200)
      out = JSON.parse(UrlHealth.new(input: { "url" => "http://example.com/plain" }).call[:body])
      assert_nil out["tls"]

      stub_request(:get, "https://example.com/boom").to_raise(Faraday::ConnectionFailed.new("refused"))
      out = JSON.parse(UrlHealth.new(input: { "url" => "https://example.com/boom" }).call[:body])
      assert_equal false, out["ok"]
      assert_match "refused", out["error"]
    end
  end
end
