# frozen_string_literal: true

module Sellers
  # A seller's own listings. They can draft and edit; only a person at
  # /admin/listings can make one live.
  class ListingsController < BaseController
    before_action :set_listing, only: %i[edit update submit pause]

    def new
      @listing = current_seller.listings.new(category: "Data", inputs: [ { "name" => "url", "type" => "string", "description" => "What to work on.", "example" => "https://example.com" } ],
                                             outputs: [ { "name" => "result", "type" => "string", "description" => "What comes back." } ])
    end

    def create
      @listing = current_seller.listings.new(listing_params)
      if @listing.save
        redirect_to seller_root_path, notice: "#{@listing.name} saved as a draft. Submit it for review when it is ready."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      redirect_to seller_root_path, alert: "Pause #{@listing.name} before editing it." unless @listing.editable?
    end

    def update
      return redirect_to(seller_root_path, alert: "Pause #{@listing.name} before editing it.") unless @listing.editable?

      if @listing.update(listing_params)
        redirect_to seller_root_path, notice: "#{@listing.name} saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def submit
      return redirect_to(seller_root_path, alert: "Add a payout address before submitting, so we know where your share goes.") if current_seller.payout_address.blank?
      return redirect_to(seller_root_path, alert: "#{@listing.name} cannot be submitted from #{@listing.status}.") unless @listing.editable?

      @listing.submit!
      Notifications::AnnounceListing.new(listing: @listing).call
      redirect_to seller_root_path, notice: "#{@listing.name} is waiting for review. We email you either way."
    end

    def pause
      @listing.pause! if @listing.live?
      redirect_to seller_root_path, notice: "#{@listing.name} is paused. Agents get a 404 until you resubmit it."
    end

    private

    def set_listing
      @listing = current_seller.listings.find(params[:id])
    end

    def listing_params
      permitted = %i[name summary description category upstream_url inputs_json outputs_json]
      permitted += %i[slug price_usdc] unless @listing&.went_live_at
      params.require(:listing).permit(*permitted)
    end
  end
end
