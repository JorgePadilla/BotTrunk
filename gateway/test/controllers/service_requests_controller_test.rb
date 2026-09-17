# frozen_string_literal: true

require "test_helper"

class ServiceRequestsControllerTest < ActionDispatch::IntegrationTest
  VALID = { email: "Buyer@Example.com", details: "We need daily court filings from three Honduran courts, as JSON.",
            service_slug: "", budget_usdc: "5.00" }.freeze

  test "a valid request is stored and redirects back to the form" do
    assert_difference("ServiceRequest.count", 1) do
      post service_requests_url, params: { service_request: VALID }
    end
    assert_redirected_to sell_path(requested: 1, anchor: "request")

    request = ServiceRequest.last
    assert_equal "buyer@example.com", request.email
    assert_equal 5_000_000, request.budget_atomic
    assert request.for_catalog_gap?
  end

  test "a request reaches us and acknowledges the buyer" do
    with_admin_email do
      perform_enqueued_jobs do
        post service_requests_url, params: { service_request: VALID }
      end
    end

    assert_equal 2, ActionMailer::Base.deliveries.size
    assert_equal [ MailHelpers::ADMIN, "buyer@example.com" ], ActionMailer::Base.deliveries.flat_map(&:to)
  end

  test "a request is a request: nothing is listed and nothing is charged" do
    assert_no_difference([ "SellerInquiry.count", "Call.count" ]) do
      post service_requests_url, params: { service_request: VALID }
    end

    assert ServiceRequest.last.pending?
  end

  test "a slug that is not ours is refused rather than stored" do
    assert_no_difference("ServiceRequest.count") do
      post service_requests_url, params: { service_request: VALID.merge(service_slug: "made-up") }
    end
    assert_response :unprocessable_entity
    assert_select "p.text-error", text: /is not a service we list/
  end

  test "a rejected form emails nobody" do
    with_admin_email do
      assert_no_enqueued_emails do
        post service_requests_url, params: { service_request: VALID.merge(email: "nope") }
      end
    end
  end

  test "an invalid request re-renders the page with errors and keeps the typed budget" do
    assert_no_difference("ServiceRequest.count") do
      post service_requests_url, params: { service_request: VALID.merge(email: "nope", budget_usdc: "abc") }
    end
    assert_response :unprocessable_entity
    assert_select "p.text-error"
    assert_select "input[name='service_request[budget_usdc]'][value='abc']"
  end

  test "the seller form still renders when the buyer form is the one that failed" do
    post service_requests_url, params: { service_request: VALID.merge(email: "nope") }

    assert_response :unprocessable_entity
    assert_select "input[name='seller_inquiry[email]']", 1, "the other half of the page must survive"
  end
end
