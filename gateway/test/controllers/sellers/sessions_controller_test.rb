# frozen_string_literal: true

require "test_helper"

module Sellers
  class SessionsControllerTest < ActionDispatch::IntegrationTest
    def sign_in_link_path
      mail = ActionMailer::Base.deliveries.last
      URI(mail.text_part.body.to_s[%r{https?://\S+/seller/sign_in/\S+}]).path
    end

    test "asking for a link emails one and says so, without saying whether the address was known" do
      perform_enqueued_jobs { post seller_sign_in_path, params: { email: "ana@example.com" } }

      assert_redirected_to seller_sign_in_path(sent: 1)
      assert_equal [ "ana@example.com" ], ActionMailer::Base.deliveries.last.to
      assert Seller.exists?(email: "ana@example.com")
    end

    test "opening the link shows a button; only pressing it signs in, and only once" do
      perform_enqueued_jobs { post seller_sign_in_path, params: { email: "ana@example.com" } }
      path = sign_in_link_path

      get path
      assert_response :success
      get seller_root_path
      assert_redirected_to seller_sign_in_path, "opening the link (as a mail scanner would) does not sign in"

      post path
      assert_redirected_to seller_root_path
      follow_redirect!
      assert_select "p", text: /ana@example.com/

      delete seller_sign_out_path
      post path
      assert_redirected_to seller_sign_in_path
      assert_equal "That sign-in link has expired or was already used. Ask for a new one.", flash[:alert]
    end

    test "a suspended seller gets the same answer and no email" do
      Seller.create!(email: "ana@example.com", status: "suspended")
      perform_enqueued_jobs { post seller_sign_in_path, params: { email: "ana@example.com" } }

      assert_redirected_to seller_sign_in_path(sent: 1)
      assert_empty ActionMailer::Base.deliveries
    end

    test "a bad address is refused on the form" do
      post seller_sign_in_path, params: { email: "not an email" }
      assert_response :unprocessable_entity
      assert_select "p.text-error"
    end

    test "sign-in emails are rate limited per network" do
      5.times { post seller_sign_in_path, params: { email: "ana@example.com" } }
      post seller_sign_in_path, params: { email: "ana@example.com" }
      assert_redirected_to seller_sign_in_path
      assert_match(/Too many sign-in emails/, flash[:alert])
    end

    test "a signed-in seller can set a name and payout address; a bad address is refused" do
      seller = Seller.create!(email: "ana@example.com")
      post seller_confirm_sign_in_path(token: seller.generate_token_for(:sign_in))

      patch seller_path, params: { seller: { name: "Acme Data", payout_address: "A" * 58 } }
      assert_redirected_to seller_root_path
      assert_equal "A" * 58, seller.reload.payout_address

      patch seller_path, params: { seller: { payout_address: "nope" } }
      assert_response :unprocessable_entity
      assert_equal "A" * 58, seller.reload.payout_address
    end

    test "suspending a seller ends their session" do
      seller = Seller.create!(email: "ana@example.com")
      post seller_confirm_sign_in_path(token: seller.generate_token_for(:sign_in))
      seller.update!(status: "suspended")

      get seller_root_path
      assert_redirected_to seller_sign_in_path
    end
  end
end
