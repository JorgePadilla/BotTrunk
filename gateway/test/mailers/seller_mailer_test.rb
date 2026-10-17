# frozen_string_literal: true

require "test_helper"

class SellerMailerTest < ActionMailer::TestCase
  include MailHelpers

  test "the acknowledgement quotes back the price and what the seller keeps" do
    mail = SellerMailer.with(inquiry: build_inquiry).acknowledgement

    assert_equal [ "seller@example.com" ], mail.to
    assert_match "Court records HN", mail.html_part.body.to_s
    assert_match "$0.25", mail.html_part.body.to_s
    assert_match "$0.2125", mail.html_part.body.to_s
    assert_match "85%", mail.html_part.body.to_s
  end

  test "the sign-in link points at the confirm page, not straight at a session" do
    seller = Seller.create!(email: "ana@example.com")
    mail = SellerMailer.with(seller: seller, token: "TOKEN123").sign_in_link

    assert_equal [ "ana@example.com" ], mail.to
    assert_match "http://example.com/seller/sign_in/TOKEN123", mail.text_part.body.to_s
    assert_match "15 minutes", mail.html_part.body.to_s
  end

  test "the invitation links to sign-in with the seller's email filled in" do
    mail = SellerMailer.with(inquiry: build_inquiry).invitation

    assert_equal [ "seller@example.com" ], mail.to
    assert_match "seller/sign_in?email=seller%40example.com", mail.text_part.body.to_s
    assert_match "Court records HN", mail.html_part.body.to_s
  end
end
