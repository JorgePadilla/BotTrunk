# frozen_string_literal: true

require "test_helper"

# Paying on Base or Solana through the real endpoint (facilitator faked).
class MultiNetworkPaidCallsTest < ActionDispatch::IntegrationTest
  BASE = "eip155:84532"
  SOLANA = "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"

  setup do
    @adapter = FakePaymentAdapter.new
    Payments::Adapters.stubs_current = @adapter
  end

  teardown { Payments::Adapters.stubs_current = nil }

  def pay(network)
    stub_upstream(body: { ok: true }.to_json)
    post paid_call_path("test-proxy"), params: "{}", headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header(network: network) }
  end

  test "a payment on Base or Solana is verified and settled against that network's option, and recorded with it" do
    with_networks do
      { BASE => NetworkHelpers::BASE_PAY_TO, SOLANA => NetworkHelpers::SOLANA_PAY_TO }.each do |network, pay_to|
        @adapter = FakePaymentAdapter.new(transaction: "TX-#{network}")
        Payments::Adapters.stubs_current = @adapter
        assert_difference("Call.count", 1) { pay(network) }
        assert_response :success

        _payload, requirements, = @adapter.settle_calls.last
        assert_equal network, requirements.network
        assert_equal pay_to, requirements.pay_to
        assert_equal network, Call.last.network
        assert_equal pay_to, Call.last.pay_to
      end
    end
  end

  test "a payment on a network we do not take is refused with the list, and the attempt is recorded with its network" do
    with_networks do
      pay("eip155:1")
      assert_response :payment_required
      assert_equal "This endpoint takes USDC on Algorand, Base or Solana; the payment was for eip155:1.", response.parsed_body["error"]
      assert_empty @adapter.verify_calls
      assert_equal "eip155:1", Event.where(name: "payment_rejected").last.properties["network"]
    end
  end

  test "Base is refused while it is not configured" do
    pay(BASE)
    assert_response :payment_required
    assert_match "takes USDC on Algorand;", response.parsed_body["error"]
  end

  test "the catalog API keeps the Algorand network for bottrunk-mcp and lists every offered one" do
    with_networks do
      get api_v1_catalog_path
      service = response.parsed_body["services"].first
      assert_equal TESTNET[:caip2], service["network"]["id"]
      assert_equal [ TESTNET[:caip2], BASE, SOLANA ], service["networks"].map { |n| n["id"] }

      get well_known_x402_path
      assert_equal [ TESTNET[:caip2], BASE, SOLANA ], response.parsed_body["resources"].first["accepts"].map { |a| a["network"] }
    end
  end

  test "stats split payments and refusals by network" do
    with_networks do
      pay(BASE)
      pay("eip155:1")
      rows = Stats::Overview.new.call[:report].networks.index_by(&:network)
      assert_equal 1, rows[BASE].settled
      assert_equal 1, rows["eip155:1"].rejected
      assert_equal 0, rows[SOLANA].settled
    end
  end
end
