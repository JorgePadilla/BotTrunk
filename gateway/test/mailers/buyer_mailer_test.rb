# frozen_string_literal: true

require "test_helper"

class BuyerMailerTest < ActionMailer::TestCase
  include MailHelpers

  test "the acknowledgement quotes back what they asked for" do
    mail = BuyerMailer.with(request: build_request).acknowledgement

    assert_equal [ "buyer@example.com" ], mail.to
    assert_match "court filings", mail.html_part.body.to_s
    assert_match "$5", mail.html_part.body.to_s
  end

  test "a request naming a service says so in the subject" do
    mail = BuyerMailer.with(request: build_request(service_slug: "scrape-markdown")).acknowledgement

    assert_match "Scrape URL to Markdown", mail.subject
  end

  test "a request naming nothing does not invent a service in the subject" do
    mail = BuyerMailer.with(request: build_request(service_slug: nil)).acknowledgement

    assert_equal "We got your request", mail.subject
    assert_match(/don't list yet/, mail.html_part.body.to_s)
  end

  test "both parts render — an email with no text part is an email a phone may not show" do
    mail = BuyerMailer.with(request: build_request).acknowledgement

    assert mail.html_part.body.to_s.present?
    assert mail.text_part.body.to_s.present?
  end
end
