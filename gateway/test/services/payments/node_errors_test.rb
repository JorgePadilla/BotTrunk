# frozen_string_literal: true

require "test_helper"

module Payments
  class NodeErrorsTest < ActiveSupport::TestCase
    # The real string, captured from a MainNet simulation of a USDC transfer
    # to an account that had not opted in.
    MISSING_OPT_IN = "receiver error: must optin, asset 31566704 missing from 2DINBOLAQTTUDSV3Q552DKDWZD4SHO5T5OCKJLZJ6F56IFJW4HTJ3JCNSU"

    test "the opt-in error tells an agent what to do and why nobody can do it for them" do
      explained = NodeErrors.explain(MISSING_OPT_IN)

      assert_match "not opted in to USDC", explained
      assert_match "Only the key holder", explained
      assert_match "rejected, not held", explained
      assert_match MISSING_OPT_IN, explained, "the original is kept: clients may match on it"
    end

    test "minimum balance, insufficient USDC, expiry and replay each get an instruction" do
      assert_match(/minimum balance/, NodeErrors.explain("account 2DIN… balance 199000 below min 200000"))
      assert_match(/enough USDC/, NodeErrors.explain("asset 31566704 overspend"))
      assert_match(/expired/, NodeErrors.explain("txn dead: round 100 outside of 50-99"))
      assert_match(/already submitted/, NodeErrors.explain("transaction already in ledger"))
    end

    test "an unrecognised reason is passed through untouched" do
      assert_equal "something new from the node", NodeErrors.explain("something new from the node")
      assert_equal "", NodeErrors.explain(nil)
    end

    test "the adapter explains a rejection instead of forwarding the raw string" do
      stub_request(:post, %r{/verify}).to_return(status: 200, body: { isValid: false, invalidReason: MISSING_OPT_IN }.to_json,
                                                 headers: { "Content-Type" => "application/json" })
      result = Adapters::Algorand.new.verify(payload: Payload.from_header(payment_header), requirements: requirements_for)

      assert result.failure?
      assert_match "not opted in to USDC", result.error
    end
  end
end
