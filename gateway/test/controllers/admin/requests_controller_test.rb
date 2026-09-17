# frozen_string_literal: true

require "test_helper"

module Admin
  class RequestsControllerTest < ActionDispatch::IntegrationTest
    setup { ENV["ADMIN_PASSWORD"] = "s3cret" }
    teardown { ENV.delete("ADMIN_PASSWORD") }

    def service_request(**attrs)
      ServiceRequest.create!({ email: "buyer@example.com",
                              details: "We need daily court filings from three Honduran courts." }.merge(attrs))
    end

    test "requires the admin password" do
      get admin_requests_url
      assert_response :unauthorized
    end

    test "lists what is waiting and what was handled" do
      waiting = service_request
      handled = service_request(email: "old@example.com")
      handled.close!(notes: "Out of scope.")

      get admin_requests_url, headers: auth

      assert_response :success
      assert_select "body", text: /#{waiting.email}/
      assert_select "body", text: /Out of scope/
    end

    test "a request naming nothing we sell is marked as a catalog gap" do
      service_request(service_slug: nil)

      get admin_requests_url, headers: auth

      assert_select "span", text: "Catalog gap"
    end

    test "a request naming a service we sell shows what we list it at" do
      service_request(service_slug: "scrape-markdown")

      get admin_requests_url, headers: auth

      assert_select "body", text: /Scrape URL to Markdown/
    end

    test "answering records the decision" do
      record = service_request

      post admin_answer_request_url(record), params: { review_notes: "Quoted 12 USDC." }, headers: auth

      assert_redirected_to admin_requests_path
      assert_equal "answered", record.reload.status
      assert_equal "Quoted 12 USDC.", record.review_notes
    end

    test "closing records the decision" do
      record = service_request

      post admin_close_request_url(record), headers: auth

      assert_equal "closed", record.reload.status
    end

    private

    def auth
      { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "s3cret") }
    end
  end
end
