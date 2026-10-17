# frozen_string_literal: true

module Sellers
  class ListingFormComponentPreview < ViewComponent::Preview
    def new_listing
      render ListingFormComponent.new(listing: sample, url: "#")
    end

    # Has been live: slug and price are locked.
    def live_listing
      render ListingFormComponent.new(listing: sample(went_live_at: Time.current, status: "paused"), url: "#", method: :patch)
    end

    def with_errors
      listing = sample(slug: "Bad Slug", upstream_url: "http://insecure.example")
      listing.valid?
      render ListingFormComponent.new(listing: listing, url: "#")
    end

    private

    def sample(**overrides)
      Listing.new({
        name: "Company lookup", slug: "company-lookup", summary: "Legal name, status and address for a registration number.",
        category: "Data", upstream_url: "https://api.example.com/lookup", price_atomic: 50_000,
        inputs: [ { "name" => "number", "type" => "string", "description" => "Registration number.", "example" => "08019995" } ],
        outputs: [ { "name" => "name", "type" => "string", "description" => "Legal name." } ]
      }.merge(overrides))
    end
  end
end
