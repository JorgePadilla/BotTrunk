# frozen_string_literal: true

module Notifications
  # A listing was submitted (tell the operator) or reviewed (tell the seller).
  class AnnounceListing
    def initialize(listing:)
      @listing = listing
    end

    def call
      mail = case @listing.status
      when "pending" then ApplicationMailer.admin_address && AdminMailer.with(listing: @listing).listing_submitted
      when "live" then SellerMailer.with(listing: @listing).listing_approved
      when "rejected" then SellerMailer.with(listing: @listing).listing_rejected
      end
      return Result.success(sent: false) unless mail

      Deliver.call(mail)
    end
  end
end
