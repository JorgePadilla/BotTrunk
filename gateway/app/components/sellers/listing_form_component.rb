# frozen_string_literal: true

module Sellers
  # The form a seller describes their API with. The schema is edited as JSON
  # (sellers are developers, and a list of field rows would need its own
  # JavaScript); every field becomes an input or output on the service page,
  # in the Bazaar entry and in the MCP tool. Slug and price lock once the
  # listing has been live.
  class ListingFormComponent < ApplicationComponent
    def initialize(listing:, url:, method: :post)
      @listing = listing
      @url = url
      @method = method
    end

    attr_reader :listing, :url, :method

    def locked? = listing.went_live_at.present?

    def categories = Listing::CATEGORIES

    def field_types = Listing::FIELD_TYPES.join(", ")
  end
end
