# frozen_string_literal: true

require "test_helper"

class AdminMailerTest < ActionMailer::TestCase
  include MailHelpers

  test "new_order gives the amount and the beneficiary in the subject line" do
    with_admin_email do
      mail = AdminMailer.with(order: build_order).new_order

      assert_equal [ MailHelpers::ADMIN ], mail.to
      assert_equal "New deposit to make — L1,000 to Juana Martínez", mail.subject
      assert_match "Invoice 42", mail.html_part.body.to_s
      assert_match "buyer@example.com", mail.html_part.body.to_s
    end
  end

  test "new_order keeps the full account number out of the email" do
    with_admin_email do
      body = AdminMailer.with(order: build_order).new_order.html_part.body.to_s

      assert_no_match "731234567890", body
      assert_match "••••7890", body
      assert_match "in the queue, not in this email", body
    end
  end

  test "nothing is built when ADMIN_EMAIL is not configured" do
    with_admin_email(nil) do
      assert_instance_of ActionMailer::Base::NullMail, AdminMailer.with(order: build_order).new_order.message
      assert_instance_of ActionMailer::Base::NullMail, AdminMailer.with(inquiry: build_inquiry).new_inquiry.message
    end
  end

  test "new_inquiry does the 85/15 arithmetic so nobody has to" do
    with_admin_email do
      mail = AdminMailer.with(inquiry: build_inquiry).new_inquiry

      assert_equal "Seller inquiry — Court records HN", mail.subject
      assert_match "$0.2125", mail.text_part.body.to_s
      assert_match "$0.0375", mail.text_part.body.to_s
    end
  end

  test "the digest subject counts the queue and names the oldest" do
    with_admin_email do
      build_order
      report = Notifications::DailyDigest.new.call[:report]
      mail = AdminMailer.with(report: report.to_h).digest

      assert_match "1 deposit waiting", mail.subject
      assert_match "Clear the queue", mail.html_part.body.to_s
    end
  end

  test "the digest says so plainly when there is nothing waiting" do
    with_admin_email do
      report = Notifications::DailyDigest.new.call[:report]

      assert_equal "BotTrunk daily — nothing waiting", AdminMailer.with(report: report.to_h).digest.subject
    end
  end

  test "a service request tells us which kind it is before we open it" do
    with_admin_email do
      mail = AdminMailer.with(request: build_request(service_slug: nil)).new_request

      assert_equal [ MailHelpers::ADMIN ], mail.to
      assert_match "something we don't sell", mail.subject
      assert_match "court filings", mail.html_part.body.to_s
    end
  end

  test "a request naming a service says what we already list it at" do
    with_admin_email do
      mail = AdminMailer.with(request: build_request(service_slug: "scrape-markdown")).new_request

      assert_match "Scrape URL to Markdown", mail.subject
      assert_match "$0.09", mail.html_part.body.to_s
    end
  end

  test "no ADMIN_EMAIL means no request alert, rather than a guess at a recipient" do
    with_admin_email(nil) do
      assert_instance_of ActionMailer::Base::NullMail, AdminMailer.with(request: build_request).new_request.message
    end
  end
end
