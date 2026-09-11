# frozen_string_literal: true

require "test_helper"

module Admin
  class InquiriesControllerTest < ActionDispatch::IntegrationTest
    setup { ENV["ADMIN_PASSWORD"] = "s3cret" }
    teardown { ENV.delete("ADMIN_PASSWORD") }

    def inquiry(**attrs)
      SellerInquiry.create!({ email: "dev@example.com", service_name: "Court records", price_atomic: 250_000,
                              upstream_url: "https://api.example.com/records" }.merge(attrs))
    end

    test "requires the admin password" do
      get admin_inquiries_url
      assert_response :unauthorized
    end

    test "lists what is waiting and what was decided" do
      waiting = inquiry
      decided = inquiry(email: "old@example.com", service_name: "Old thing")
      decided.reject!(notes: "Not a fit.")

      get admin_inquiries_url, headers: auth
      assert_response :success
      assert_select "h2", text: "To review · 1"
      assert_select "td", text: "Old thing"
      assert_select "form[action='#{admin_approve_inquiry_path(waiting)}']"
      assert_match "Not a fit.", response.body
    end

    test "approving records the decision and emails the seller" do
      record = inquiry

      with_admin_email do
        assert_enqueued_emails 1 do
          post admin_approve_inquiry_url(record), params: { review_notes: "At 0.02." }, headers: auth
        end
      end
      assert_redirected_to admin_inquiries_path
      assert_equal "approved", record.reload.status
      assert_equal "At 0.02.", record.review_notes
      assert_match "dev@example.com was emailed", flash[:notice]
    end

    test "rejecting also emails, because silence is the one answer a seller should not get" do
      record = inquiry

      with_admin_email do
        assert_enqueued_emails 1 do
          post admin_reject_inquiry_url(record), headers: auth
        end
      end
      assert_equal "rejected", record.reload.status
    end

    private

    def auth
      { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "s3cret") }
    end
  end
end
