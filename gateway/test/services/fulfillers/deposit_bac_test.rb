# frozen_string_literal: true

require "test_helper"

module Fulfillers
  class DepositBacTest < ActiveSupport::TestCase
    def tier = Catalog::Service.find("deposit-bac-1000")

    test "opens an order awaiting payment and answers 202 with a status url" do
      result = DepositBac.new(input: { "beneficiary_name" => "  María  Pérez ", "account_number" => "1234-5678-90", "concept" => "Factura 7" }, service: tier).call

      assert result.success?
      assert_equal 202, result[:status]
      order = result[:order]
      assert_equal "awaiting_payment", order.status
      assert_equal 1_000, order.amount_hnl
      assert_equal "María Pérez", order.beneficiary_name
      assert_equal "1234567890", order.account_number
      assert_equal 42_510_122, order.price_atomic
      assert_equal BigDecimal("24.70"), order.rate_hnl_per_usd
      body = JSON.parse(result[:body])
      assert_equal order.token, body["order_id"]
      assert_equal "pending", body["status"]
      assert_equal "https://api.bottrunk.test/orders/#{order.token}", body["status_url"]
      assert_nil body["account_number"]
    end

    test "rejects bad input with 422 and opens nothing" do
      [
        { "beneficiary_name" => "X", "account_number" => "123456" },
        { "beneficiary_name" => "Ana", "account_number" => "12ab" },
        { "beneficiary_name" => "Ana", "account_number" => "123456", "contact_email" => "nope" },
        { "beneficiary_name" => "Ana", "account_number" => "123456", "concept" => "x" * 61 }
      ].each do |input|
        result = DepositBac.new(input: input, service: tier).call
        assert_equal 422, result[:status], input.inspect
        assert_nil result[:order]
      end
      assert_equal 0, DepositOrder.count
    end

    test "limits one account to three settled deposits a day" do
      3.times do |i|
        DepositOrder.create!(service_slug: "deposit-bac-1000", amount_hnl: 1000, price_atomic: 1, rate_hnl_per_usd: 24.7, fee_bps: 500,
                             beneficiary_name: "Ana", account_number: "123456", status: i.zero? ? "delivered" : "pending")
      end
      result = DepositBac.new(input: { "beneficiary_name" => "Ana", "account_number" => "123456" }, service: tier).call
      assert_equal 429, result[:status]

      DepositOrder.create!(service_slug: "deposit-bac-1000", amount_hnl: 1000, price_atomic: 1, rate_hnl_per_usd: 24.7, fee_bps: 500,
                           beneficiary_name: "Ana", account_number: "999999", status: "cancelled")
      result = DepositBac.new(input: { "beneficiary_name" => "Ana", "account_number" => "999999" }, service: tier).call
      assert_equal 202, result[:status], "cancelled orders do not count"
    end
  end
end
