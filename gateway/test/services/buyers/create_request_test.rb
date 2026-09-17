# frozen_string_literal: true

require "test_helper"

module Buyers
  class CreateRequestTest < ActiveSupport::TestCase
    DETAILS = "We need daily court filings from three Honduran courts, as JSON."

    test "converts a USDC budget to atomic units without floats" do
      result = CreateRequest.new(email: "a@b.co", details: DETAILS, budget_usdc: "0.1").call

      assert result.success?
      assert_equal 100_000, result[:request].budget_atomic
    end

    test "a budget we cannot read is dropped, not guessed at — the request still lands" do
      result = CreateRequest.new(email: "a@b.co", details: DETAILS, budget_usdc: "about five").call

      assert result.success?, "an unreadable budget must not cost someone their request"
      assert_nil result[:request].budget_atomic
    end

    test "the email is normalised the way a seller's is" do
      result = CreateRequest.new(email: "  Buyer@Example.COM ", details: DETAILS).call

      assert_equal "buyer@example.com", result[:request].email
    end

    test "a blank slug is stored as nothing rather than an empty string" do
      result = CreateRequest.new(email: "a@b.co", details: DETAILS, service_slug: "").call

      assert_nil result[:request].service_slug
      assert result[:request].for_catalog_gap?
    end

    test "an invalid request fails with the errors rather than saving" do
      result = CreateRequest.new(email: "nope", details: "short").call

      assert result.failure?
      assert_equal :invalid, result.code
      assert_equal 0, ServiceRequest.count
    end
  end
end
