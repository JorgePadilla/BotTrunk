# frozen_string_literal: true

require "test_helper"

module Payments
  class BuildRequirementsTest < ActiveSupport::TestCase
    test "builds an exact USDC requirement on the configured network" do
      result = BuildRequirements.new(service: service).call
      assert result.success?

      req = result[:requirements]
      assert_equal "exact", req.scheme
      assert_equal TESTNET[:caip2], req.network
      assert_equal TESTNET[:usdc_asa], req.asset
      assert_equal 5_000, req.amount # $0.005 in µUSDC
      assert_equal TEST_PAY_TO, req.pay_to
      assert_equal "https://api.bottrunk.test/s/scrape-markdown", req.resource
      assert_equal({ decimals: 6, tag: "x402-global-challenge" }, req.extra)
    end

    test "serializes with x402 field names and a string amount" do
      h = requirements_for.to_h
      assert_equal "5000", h[:amount]
      assert_equal TEST_PAY_TO, h[:payTo]
      assert_equal 60, h[:maxTimeoutSeconds]
      assert_equal "application/json", h[:mimeType]
    end

    test "402 body carries accepts and the bazaar extension" do
      body = BuildRequirements.body_for(service: service, requirements: requirements_for)
      assert_equal 2, body[:x402Version]
      assert_equal 1, body[:accepts].size
      assert_equal "POST", body.dig(:extensions, :bazaar, :info, :input, :method)
      assert_equal "string", body.dig(:extensions, :bazaar, :info, :input, :params, "url")
    end

    test "fails when payTo is not configured" do
      config = Rails.configuration.x402.dup
      config.pay_to = nil
      result = BuildRequirements.new(service: service, config: config).call
      assert result.failure?
      assert_equal :not_configured, result.code
    end

    test "prices never go through floats" do
      svc = Catalog::Service.find("verify-business-hn")
      assert_equal 5_000_000, svc.price_atomic
    end
  end
end
