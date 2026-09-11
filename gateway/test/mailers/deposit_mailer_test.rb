# frozen_string_literal: true

require "test_helper"

class DepositMailerTest < ActionMailer::TestCase
  include MailHelpers

  test "received tells the buyer the amount, the beneficiary and the 24-hour promise" do
    mail = DepositMailer.with(order: build_order).received

    assert_equal [ "buyer@example.com" ], mail.to
    assert_match "L1,000", mail.subject
    assert_match "Juana Martínez", mail.subject
    [ mail.html_part, mail.text_part ].each do |part|
      body = part.body.to_s
      assert_match "within 24 hours", body
      assert_match "L1,000", body
      assert_match "$42.51", body
      assert_match "L26.2", body
    end
  end

  test "received never repeats the full account number" do
    body = DepositMailer.with(order: build_order).received.html_part.body.to_s

    assert_no_match "731234567890", body
    assert_match "••••7890", body
  end

  test "delivered leads with the bank receipt reference" do
    order = build_order
    order.deliver!(receipt_reference: "BAC-99881", notes: "Sent 9:40am")
    mail = DepositMailer.with(order: order).delivered

    assert_match "BAC-99881", mail.html_part.body.to_s
    assert_match "BAC-99881", mail.text_part.body.to_s
    assert_match "Sent 9:40am", mail.html_part.body.to_s
  end

  test "refunded links the refund transaction and says nothing was kept" do
    order = build_order
    order.refund!(transaction_id: "KFCOJ5GXBDZKTHAKBKYFULKICYDMYAYW", notes: "Account closed")
    mail = DepositMailer.with(order: order).refunded

    assert_match "allo.info/tx/KFCOJ5GXBDZKTHAKBKYFULKICYDMYAYW", mail.text_part.body.to_s
    assert_match "Nothing was kept", mail.html_part.body.to_s
    assert_match "Account closed", mail.text_part.body.to_s
  end

  test "an order with no contact email produces nothing to send" do
    mail = DepositMailer.with(order: build_order(contact_email: nil)).received

    assert_nil mail.message.to
    assert_instance_of ActionMailer::Base::NullMail, mail.message
  end
end
