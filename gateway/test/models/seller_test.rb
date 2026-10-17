# frozen_string_literal: true

require "test_helper"

class SellerTest < ActiveSupport::TestCase
  test "a new seller gets a signing secret, stored encrypted" do
    seller = Seller.create!(email: " Ana@Example.COM ")
    assert_equal "ana@example.com", seller.email
    assert_match(/\Abts_\w{40}\z/, seller.signing_secret)
    raw = Seller.connection.select_value("SELECT signing_secret FROM sellers WHERE id = #{seller.id}")
    assert_not_includes raw, seller.signing_secret
  end

  test "rotating the secret replaces it" do
    seller = Seller.create!(email: "ana@example.com")
    old = seller.signing_secret
    seller.rotate_signing_secret!
    assert_not_equal old, seller.reload.signing_secret
  end

  test "a payout address must look like an Algorand address" do
    seller = Seller.new(email: "ana@example.com", payout_address: "not-an-address")
    assert_not seller.valid?
    seller.payout_address = " #{'a' * 58} "
    assert seller.valid?, "normalised to upper case, spaces trimmed"
    seller.payout_address = ""
    assert seller.valid?, "blank means not set yet"
    assert_nil seller.payout_address
  end

  test "a sign-in link works once and expires" do
    seller = Seller.create!(email: "ana@example.com")
    token = seller.generate_token_for(:sign_in)
    assert_equal seller, Seller.find_by_token_for(:sign_in, token)

    seller.update!(last_signed_in_at: Time.current)
    assert_nil Seller.find_by_token_for(:sign_in, token), "spent by signing in"

    fresh = seller.generate_token_for(:sign_in)
    travel(Seller::SIGN_IN_LINK_TTL + 1.minute) { assert_nil Seller.find_by_token_for(:sign_in, fresh) }
  end
end
