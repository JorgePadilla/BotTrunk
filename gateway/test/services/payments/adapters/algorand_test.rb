# frozen_string_literal: true

require "test_helper"

module Payments
  module Adapters
    class AlgorandTest < ActiveSupport::TestCase
      FACILITATOR = "https://facilitator.test"

      setup do
        @adapter = Algorand.new(base_url: FACILITATOR)
        @payload = Payload.from_header(payment_header)
        @requirements = requirements_for
      end

      test "verify posts a complete v2 envelope and reads isValid" do
        stub = stub_request(:post, "#{FACILITATOR}/verify")
          .with { |req|
            body = JSON.parse(req.body)
            pp = body["paymentPayload"]
            body["x402Version"] == 2 && body["paymentRequirements"]["payTo"] == TEST_PAY_TO && pp["scheme"] == "exact" &&
              pp["resource"]["url"] == "https://api.bottrunk.test/s/scrape-markdown" &&
              pp["accepted"]["extra"]["tag"] == "x402-global-challenge" &&
              pp["extensions"]["bazaar"]["schema"].is_a?(Hash) &&
              !body["paymentRequirements"].key?("resource")
          }
          .to_return(status: 200, body: { isValid: true, payer: "PAYER1" }.to_json, headers: { "Content-Type" => "application/json" })

        ext = { bazaar: Payments::BuildRequirements.bazaar_extension(service) }
        result = @adapter.verify(payload: @payload, requirements: @requirements, extensions: ext)
        assert result.success?
        assert_equal "PAYER1", result[:payer]
        assert_requested stub
      end

      test "a client's own accepted/resource/extensions are left untouched" do
        raw = @payload.to_h.merge("accepted" => { "scheme" => "exact", "custom" => true }, "resource" => { "url" => "https://client.example/x" })
        payload = Payments::Payload.new(raw: raw)
        stub = stub_request(:post, "#{FACILITATOR}/verify")
          .with { |req| pp = JSON.parse(req.body)["paymentPayload"]; pp["accepted"]["custom"] == true && pp["resource"]["url"] == "https://client.example/x" }
          .to_return(status: 200, body: { isValid: true, payer: "P" }.to_json)
        assert @adapter.verify(payload: payload, requirements: @requirements).success?
        assert_requested stub
      end

      test "verify surfaces invalidReason" do
        stub_request(:post, "#{FACILITATOR}/verify").to_return(status: 200, body: { isValid: false, invalidReason: "insufficient_funds" }.to_json)
        result = @adapter.verify(payload: @payload, requirements: @requirements)
        assert result.failure?
        assert_equal "insufficient_funds", result.error
        assert_equal :invalid_payment, result.code
      end

      test "settle returns a receipt with the transaction id" do
        stub_request(:post, "#{FACILITATOR}/settle").to_return(status: 200, body: { success: true, transaction: "TX1", network: TESTNET[:caip2], payer: "PAYER1" }.to_json)
        result = @adapter.settle(payload: @payload, requirements: @requirements)
        assert result.success?
        assert_equal "TX1", result[:receipt].transaction
        assert_equal Base64.strict_encode64(result[:receipt].to_h.to_json), result[:receipt].to_header
      end

      test "non-2xx and network errors become failures, never exceptions" do
        stub_request(:post, "#{FACILITATOR}/settle").to_return(status: 503, body: "down")
        assert_equal :facilitator_error, @adapter.settle(payload: @payload, requirements: @requirements).code

        stub_request(:post, "#{FACILITATOR}/verify").to_timeout
        assert_equal :facilitator_unreachable, @adapter.verify(payload: @payload, requirements: @requirements).code
      end
    end
  end
end
