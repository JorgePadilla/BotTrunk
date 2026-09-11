# frozen_string_literal: true

require "test_helper"

class SellerInquiryTest < ActiveSupport::TestCase
  def inquiry(**overrides)
    SellerInquiry.new({ email: "dev@example.com", service_name: "Court records", price_atomic: 250_000,
                        upstream_url: "https://api.example.com/records" }.merge(overrides))
  end

  test "a new inquiry is pending: nothing a seller submits is listed by submitting it" do
    record = inquiry
    assert record.save
    assert record.pending?
    assert_equal [ record ], SellerInquiry.pending.to_a
    assert_empty SellerInquiry.reviewed
  end

  test "approving and rejecting each record who decided and when" do
    approved = inquiry.tap(&:save!)
    approved.approve!(notes: "At 0.02 rather than 0.25.")

    assert_equal "approved", approved.status
    assert approved.reviewed_at.present?
    assert_equal "At 0.02 rather than 0.25.", approved.review_notes
    assert_not approved.pending?

    rejected = inquiry(email: "other@example.com").tap(&:save!)
    rejected.reject!
    assert_equal "rejected", rejected.status
    assert_equal 2, SellerInquiry.reviewed.count
  end

  # An upstream URL is one we will make requests to on an agent's behalf, so a
  # private address accepted here is an SSRF that arrives on a delay.
  test "an upstream URL pointing into private space is refused" do
    [ "http://localhost:3000/admin", "http://db.internal/", "http://127.0.0.1/" ].each do |url|
      record = inquiry(upstream_url: url)
      assert_not record.valid?, url
      assert_match(/public address/, record.errors[:upstream_url].to_sentence, url)
    end
  end

  test "a host that does not resolve yet is allowed, because sellers register before DNS" do
    assert inquiry(upstream_url: "https://nxdomain.test/api").valid?
  end

  test "a price nobody could pay is a typo, not a listing" do
    assert_not inquiry(price_atomic: 0).valid?
    assert_not inquiry(price_atomic: -1).valid?
    assert_not inquiry(price_atomic: SellerInquiry::MIN_PRICE_ATOMIC - 1).valid?, "below a cent the commission rounds to nothing"
    assert_not inquiry(price_atomic: SellerInquiry::MAX_PRICE_ATOMIC + 1).valid?
    assert inquiry(price_atomic: SellerInquiry::MIN_PRICE_ATOMIC).valid?
    assert inquiry(price_atomic: SellerInquiry::MAX_PRICE_ATOMIC).valid?
  end

  test "an unreadable price says so, instead of claiming the box was empty" do
    record = inquiry(price_atomic: nil)

    assert_not record.valid?
    assert_match(/must be a number in USDC/, record.errors[:price_atomic].to_sentence)
  end

  # Tightening a rule must never strand a row that predates it: a person still
  # has to be able to approve or reject whatever is already in the queue.
  test "a row that no longer meets the limits can still be reviewed" do
    record = inquiry
    record.save!
    record.update_columns(price_atomic: 1, upstream_url: "http://taphn")

    assert_nothing_raised { record.reload.reject!(notes: "Below the minimum.") }
    assert_equal "rejected", record.reload.status
  end

  test "but changing the price or the URL is judged by today's rules" do
    record = inquiry.tap(&:save!)

    record.price_atomic = 1
    assert_not record.valid?

    record.reload.upstream_url = "http://localhost/admin"
    assert_not record.valid?
  end
end
