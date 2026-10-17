# frozen_string_literal: true

# Sellers and their listings, for the tests that need one.
module SellerHelpers
  PAYOUT = "SELLERPAYOUT#{'A' * 46}".freeze

  def build_seller(**overrides)
    Seller.create!({ email: "seller-#{SecureRandom.hex(3)}@example.com", payout_address: PAYOUT,
                     terms_version: Seller::TERMS_VERSION, terms_accepted_at: Time.current }.merge(overrides))
  end

  def build_listing(seller: build_seller, **overrides)
    seller.listings.create!({
      slug: "company-lookup", name: "Company lookup", summary: "Legal name for a registration number.",
      category: "Data", upstream_url: "https://api.seller.example/lookup", price_atomic: 50_000,
      inputs: [ { "name" => "number", "type" => "string", "description" => "Registration number.", "example" => "08019995" } ],
      outputs: [ { "name" => "name", "type" => "string", "description" => "Legal name." } ]
    }.merge(overrides))
  end

  def live_listing(**overrides)
    listing = build_listing(**overrides)
    listing.submit!
    listing.approve!
    Current.listing_services = nil
    listing
  end

  def sign_in_as(seller)
    post seller_confirm_sign_in_path(token: seller.generate_token_for(:sign_in))
  end
end
