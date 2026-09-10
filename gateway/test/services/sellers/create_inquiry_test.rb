# frozen_string_literal: true

require "test_helper"

module Sellers
  class CreateInquiryTest < ActiveSupport::TestCase
    test "converts USDC to atomic units without floats" do
      result = CreateInquiry.new(email: "a@b.co", service_name: "S", upstream_url: "https://x.y/z", price_usdc: "0.1").call
      assert result.success?
      assert_equal 100_000, result[:inquiry].price_atomic
    end

    test "rejects a zero or unparsable price" do
      assert_equal :invalid, CreateInquiry.new(email: "a@b.co", service_name: "S", upstream_url: "https://x.y/z", price_usdc: "0").call.code
      assert_equal :invalid, CreateInquiry.new(email: "a@b.co", service_name: "S", upstream_url: "https://x.y/z", price_usdc: "1e").call.code
    end
  end
end
