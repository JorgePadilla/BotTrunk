# frozen_string_literal: true

require "test_helper"

module Admin
  class ListingsControllerTest < ActionDispatch::IntegrationTest
    setup { ENV["ADMIN_PASSWORD"] = "s3cret" }
    teardown { ENV.delete("ADMIN_PASSWORD") }

    def auth = { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "s3cret") }

    test "approving lists the API everywhere at once and tells the seller" do
      listing = build_listing
      listing.submit!

      get admin_listings_path, headers: auth
      assert_select "span", text: "Company lookup"

      perform_enqueued_jobs { post admin_approve_listing_path(listing), params: { review_notes: "Welcome." }, headers: auth }
      assert_equal "live", listing.reload.status
      assert_equal "Company lookup is live on BotTrunk", ActionMailer::Base.deliveries.last.subject

      get api_v1_catalog_path
      assert_includes response.parsed_body["services"].map { |s| s["slug"] }, "company-lookup"
      get service_path("company-lookup")
      assert_response :success
    end

    test "rejecting tells the seller why" do
      listing = build_listing
      listing.submit!
      perform_enqueued_jobs { post admin_reject_listing_path(listing), params: { review_notes: "The endpoint answers 500." }, headers: auth }

      assert_equal "rejected", listing.reload.status
      assert_match "The endpoint answers 500.", ActionMailer::Base.deliveries.last.text_part.body.to_s
    end

    test "only a pending listing can be reviewed" do
      listing = build_listing
      post admin_approve_listing_path(listing), headers: auth
      assert_equal "draft", listing.reload.status
    end
  end
end
