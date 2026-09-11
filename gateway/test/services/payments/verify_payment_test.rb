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

    # x402 v2 keeps the scheme and network inside `accepted`; v1 kept them at
    # the top level. Reading only the top level rejected every strict v2
    # client — including bottrunk-mcp, the package /docs tells agents to use —
    # with "scheme mismatch", before the facilitator was ever asked.
    test "a v2 payload with scheme and network inside accepted is verified" do
      adapter = FakePaymentAdapter.new(payer: "PAYER2")
      payload = Payload.from_header(payment_header(style: :v2))

      assert_equal "exact", payload.scheme
      assert_equal TESTNET[:caip2], payload.network
      assert VerifyPayment.new(payload: payload, requirements: requirements_for, adapter: adapter).call.success?
    end

    test "a v1 payload with them at the top level still pays" do
      payload = Payload.from_header(payment_header(style: :v1))

      assert_equal "exact", payload.scheme
      assert_equal TESTNET[:caip2], payload.network
      assert VerifyPayment.new(payload: payload, requirements: requirements_for, adapter: FakePaymentAdapter.new).call.success?
    end

    test "a v2 payload on the wrong network is caught inside accepted" do
      payload = Payload.from_header(payment_header(network: Networks.algorand(:mainnet)[:caip2], style: :v2))
      result = VerifyPayment.new(payload: payload, requirements: requirements_for, adapter: FakePaymentAdapter.new).call

      assert result.failure?
      assert_match(/network/, result.error)
    end

    test "a payload carrying neither shape is refused, not passed on" do
      adapter = FakePaymentAdapter.new
      payload = Payload.from_header(Base64.strict_encode64({ x402Version: 2, payload: {} }.to_json))
      result = VerifyPayment.new(payload: payload, requirements: requirements_for, adapter: adapter).call

      assert_equal "scheme mismatch", result.error
      assert_empty adapter.verify_calls
    end

    test "Payload.from_header returns nil for garbage" do
      assert_nil Payload.from_header("not base64!!")
      assert_nil Payload.from_header(Base64.strict_encode64("[1,2]"))
      assert_nil Payload.from_header("")
    end
  end
end
