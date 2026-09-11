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
end
