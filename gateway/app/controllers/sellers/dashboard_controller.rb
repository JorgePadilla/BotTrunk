# frozen_string_literal: true

module Sellers
  # /seller — the seller's home. Listings and earnings arrive with B2 and B3;
  # for now it is the account itself.
  class DashboardController < BaseController
    def show; end

    def update
      if current_seller.update(params.require(:seller).permit(:name, :payout_address))
        redirect_to seller_root_path, notice: "Saved."
      else
        render :show, status: :unprocessable_entity
      end
    end
  end
end
