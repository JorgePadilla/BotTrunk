# frozen_string_literal: true

require "test_helper"

module Gateway
  class ProxyCallTest < ActiveSupport::TestCase
    test "forwards the body and returns status, body and latency" do
      stub_upstream(body: { markdown: "# Hi" }.to_json)
      result = ProxyCall.new(service: service, body: { url: "https://example.com" }.to_json).call
      assert result.success?
      assert_equal 200, result[:status]
      assert_equal "# Hi", JSON.parse(result[:body])["markdown"]
      assert_kind_of Integer, result[:latency_ms]
      assert_requested :post, Catalog::Service::DEFAULT_UPSTREAM, body: { url: "https://example.com" }.to_json
    end

    test "5xx upstream is a failure carrying the status" do
      stub_upstream(status: 502, body: "bad gateway")
      result = ProxyCall.new(service: service, body: "{}").call
      assert result.failure?
      assert_equal :upstream_error, result.code
      assert_equal 502, result[:status]
    end

    test "4xx upstream is passed through as success (the caller's problem, still paid)" do
      stub_upstream(status: 422, body: { error: "bad url" }.to_json)
      result = ProxyCall.new(service: service, body: "{}").call
      assert result.success?
      assert_equal 422, result[:status]
    end

    test "timeouts become failures" do
      stub_request(:post, Catalog::Service::DEFAULT_UPSTREAM).to_timeout
      assert_equal :upstream_unreachable, ProxyCall.new(service: service, body: "{}").call.code
    end
  end
end
