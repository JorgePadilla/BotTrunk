# frozen_string_literal: true

require "test_helper"

module Fulfillers
  class BtcDeliveryTest < ActiveSupport::TestCase
    ADDRESS = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"

    setup { Rates::UsdBtc.stub_rate = "100000" }
    teardown { Rates::UsdBtc.stub_rate = nil }

    def service = Catalog::Service.find("btc-500")

    test "opens an order with the quote frozen into it" do
      result = BtcDelivery.new(input: { "btc_address" => ADDRESS }, service: service).call

      assert result.success?
      assert_equal 202, result[:status]

      order = result[:order]
      assert_equal "btc-500", order.service_slug
      assert_equal 500_000_000, order.price_atomic
      assert_equal ADDRESS, order.params["btc_address"]

      quote = order.params["quote"]
      assert_equal "0.00454545", quote["btc_delivered"], "what the buyer was promised, recorded"
      assert_equal "110000.0", quote["your_rate_usd_per_btc"]
      assert_equal "100000.0", quote["spot_usd_per_btc"]
      assert_equal 10.0, quote["spread_percent"]
      assert_equal "454.55", quote["value_at_spot_usd"]
    end

    test "an address that is not an address is refused for free" do
      [ "", "not-an-address", "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", "bc1", "bc1!nvalid$chars" ].each do |bad|
        result = BtcDelivery.new(input: { "btc_address" => bad }, service: service).call
        assert_equal 422, result[:status], bad.inspect
        assert_match(/bitcoin address/, JSON.parse(result[:body])["error"])
      end

      assert_equal 0, WorkOrder.count, "nothing opened for a request we refused"
    end

    test "legacy and bech32 addresses are both accepted" do
      [ ADDRESS, "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2", "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy" ].each do |address|
        result = BtcDelivery.new(input: { "btc_address" => address }, service: service).call
        assert_equal 202, result[:status], address
      end
    end

    # A shape check is not a checksum: bc1… with a character missing still
    # looks like an address, and only the operator's second look catches it.
    # That limit is stated on the service page rather than papered over here.
    test "a well-formed address that is merely wrong still passes the shape check" do
      result = BtcDelivery.new(input: { "btc_address" => ADDRESS.chop }, service: service).call
      assert_equal 202, result[:status]
    end

    test "no fresh price means no sale, and nothing is charged" do
      Rates::UsdBtc.stub_rate = nil
      Rails.cache.delete(Rates::UsdBtc::CACHE_KEY)
      stub_request(:get, Rates::UsdBtc::FEED).to_return(status: 500)

      result = BtcDelivery.new(input: { "btc_address" => ADDRESS }, service: service).call
      assert_equal 503, result[:status], "a quote we cannot stand behind is refused"
      assert_match(/Nothing was charged/, JSON.parse(result[:body])["error"])
      assert_equal 0, WorkOrder.count
    end

    test "capacity is small on purpose and refuses rather than overpromising" do
      service.job_capacity.times do
        WorkOrder.create!(service_slug: "btc-500", price_atomic: 500_000_000, brief: ADDRESS, status: "pending")
      end

      result = BtcDelivery.new(input: { "btc_address" => ADDRESS }, service: service).call
      assert_equal 429, result[:status]
    end
  end
end
