# frozen_string_literal: true

require "test_helper"

class SellerInquiriesControllerTest < ActionDispatch::IntegrationTest
  VALID = { email: "Dev@Example.com", service_name: "PDF to JSON", upstream_url: "https://api.example.com/pdf", price_usdc: "0.02", notes: "" }.freeze

  test "valid inquiry is stored with the price in atomic units and redirects" do
    assert_difference("SellerInquiry.count", 1) do
      post seller_inquiries_url, params: { seller_inquiry: VALID }
    end
    assert_redirected_to sell_path(submitted: 1)

    inquiry = SellerInquiry.last
    assert_equal "dev@example.com", inquiry.email
    assert_equal 20_000, inquiry.price_atomic
    assert_nil inquiry.notes
  end

  test "a valid inquiry reaches us and acknowledges the seller" do
    with_admin_email do
      assert_enqueued_emails 2 do
        post seller_inquiries_url, params: { seller_inquiry: VALID }
      end
    end
  end

  test "a submission is a request, not a listing" do
    post seller_inquiries_url, params: { seller_inquiry: VALID }

    assert SellerInquiry.last.pending?, "nothing a seller submits may list itself"
  end

  test "an upstream URL inside our own network is refused at the form" do
    assert_no_difference("SellerInquiry.count") do
      post seller_inquiries_url, params: { seller_inquiry: VALID.merge(upstream_url: "http://localhost:3000/admin") }
    end
    assert_response :unprocessable_entity
    assert_select "p.text-error", text: /public address/
  end

  test "a rejected form emails nobody" do
    with_admin_email do
      assert_no_enqueued_emails do
        post seller_inquiries_url, params: { seller_inquiry: VALID.merge(email: "nope") }
      end
    end
  end

  test "invalid inquiry re-renders the form with errors and keeps the typed price" do
    assert_no_difference("SellerInquiry.count") do
      post seller_inquiries_url, params: { seller_inquiry: VALID.merge(email: "nope", upstream_url: "ftp://x", price_usdc: "abc") }
    end
    assert_response :unprocessable_entity
    assert_select "p.text-error"
    assert_select "input[name='seller_inquiry[price_usdc]'][value='abc']"
  end
end
