# frozen_string_literal: true

require "test_helper"

module Payments
  class VerifyPaymentTest < ActiveSupport::TestCase
    test "rejects a missing header before touching the adapter" do
      adapter = FakePaymentAdapter.new
      result = VerifyPayment.new(payload: nil, requirements: requirements_for, adapter: adapter).call
      assert result.failure?
      assert_equal :invalid_payment, result.code
      assert_empty adapter.verify_calls
    end

    test "rejects a network mismatch" do
      payload = Payload.from_header(payment_header(network: Networks.algorand(:mainnet)[:caip2]))
      result = VerifyPayment.new(payload: payload, requirements: requirements_for, adapter: FakePaymentAdapter.new).call
      assert result.failure?
      assert_match(/network/, result.error)
    end

    test "delegates a well-formed payload to the adapter" do
      adapter = FakePaymentAdapter.new(payer: "PAYER1")
      payload = Payload.from_header(payment_header)
      result = VerifyPayment.new(payload: payload, requirements: requirements_for, adapter: adapter).call
      assert result.success?
      assert_equal "PAYER1", result[:payer]
      assert_equal 1, adapter.verify_calls.size
    end

    test "Payload.from_header returns nil for garbage" do
      assert_nil Payload.from_header("not base64!!")
      assert_nil Payload.from_header(Base64.strict_encode64("[1,2]"))
      assert_nil Payload.from_header("")
    end
  end
end
