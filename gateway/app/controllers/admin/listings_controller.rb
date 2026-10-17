# frozen_string_literal: true

module Admin
  # Seller listings waiting for a person. Approving one puts it in the
  # catalog, the Bazaar and the MCP tools at once; the seller is emailed
  # either way.
  class ListingsController < BaseController
    def index
      @pending = Listing.pending.includes(:seller)
      @others = Listing.where.not(status: "pending").includes(:seller).order(updated_at: :desc).limit(50)
    end

    def approve = review(:approve!, "is live")

    def reject = review(:reject!, "was rejected")

    private

    def review(action, label)
      listing = Listing.find(params[:id])
      return redirect_to(admin_listings_path, alert: "#{listing.name} is not waiting for review.") unless listing.pending?

      listing.public_send(action, notes: params[:review_notes])
      Notifications::AnnounceListing.new(listing: listing).call
      redirect_to admin_listings_path, notice: "#{listing.name} #{label}. #{listing.seller.email} was emailed."
    end
  end
end
