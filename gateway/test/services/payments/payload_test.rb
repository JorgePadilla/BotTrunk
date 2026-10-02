# frozen_string_literal: true

require "test_helper"

module Payments
  class PayloadTest < ActiveSupport::TestCase
    def headers(env) = ActionDispatch::Http::Headers.from_hash(env)

    test "header_in prefers the x402 v2 header over the v1 one" do
      assert_equal "v2", Payload.header_in(headers("HTTP_PAYMENT_SIGNATURE" => "v2", "HTTP_X_PAYMENT" => "v1"))
    end

    test "header_in falls back to X-PAYMENT for v1 clients" do
      assert_equal "v1", Payload.header_in(headers("HTTP_PAYMENT_SIGNATURE" => "", "HTTP_X_PAYMENT" => "v1"))
    end

    test "header_in is nil when no payment was sent" do
      assert_nil Payload.header_in(headers({}))
      assert_nil Payload.header_in(headers("HTTP_X_PAYMENT" => " "))
    end
  end
end
