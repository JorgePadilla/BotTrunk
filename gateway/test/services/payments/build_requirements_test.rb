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
      assert_equal 90_000, req.amount # $0.09 in µUSDC
      assert_equal TEST_PAY_TO, req.pay_to
      assert_equal "https://api.bottrunk.test/s/scrape-markdown", req.resource
      assert_equal 6, req.extra[:decimals]
      assert_equal "x402-global-challenge", req.extra[:tag]
      assert_equal Rails.configuration.x402.fee_payer, req.extra[:feePayer]
    end

    test "serializes with x402 field names and a string amount" do
      h = requirements_for.to_h
      assert_equal "90000", h[:amount]
      assert_equal TEST_PAY_TO, h[:payTo]
      assert_equal 60, h[:maxTimeoutSeconds]
      assert_equal "application/json", h[:mimeType]
    end

    test "402 body carries accepts and a bazaar extension shaped like the reference SDK" do
      body = BuildRequirements.body_for(service: service, requirements: requirements_for)
      assert_equal 2, body[:x402Version]
      assert_equal 1, body[:accepts].size
      assert_equal "https://api.bottrunk.test/s/scrape-markdown", body.dig(:resource, :url)

      info = body.dig(:extensions, :bazaar, :info)
      assert_equal({ type: "http", method: "POST", bodyType: "json", body: { "url" => "https://example.com/pricing", "render_js" => false, "selector" => "…" } }, info[:input])
      assert_equal "json", info.dig(:output, :type)
      assert_equal 412, info.dig(:output, :example, "word_count")

      schema = body.dig(:extensions, :bazaar, :schema)
      assert_equal "http", schema.dig(:properties, :input, :properties, :type, :const)
      assert_equal false, schema.dig(:properties, :input, :additionalProperties)
      assert_equal %w[type method bodyType body], schema.dig(:properties, :input, :required)
      assert_equal "string", schema.dig(:properties, :input, :properties, :body, :properties, "url", :type)
      assert_equal %w[type], schema.dig(:properties, :output, :required)
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
