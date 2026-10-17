# frozen_string_literal: true

module Sellers
  # /seller — the seller's home: their APIs, what they earned and are owed,
  # recent calls, payouts, and the secret their API checks our calls with.
  class DashboardController < BaseController
    before_action :load_overview, only: %i[show update]

    def show; end

    def rotate_secret
      current_seller.rotate_signing_secret!
      redirect_to seller_root_path(anchor: "secret"), notice: "New secret in place. Calls are signed with it from now on."
    end

    def update
      if current_seller.update(params.require(:seller).permit(:name, :payout_address))
        redirect_to seller_root_path, notice: "Saved."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def load_overview
      @overview = Sellers::Overview.new(seller: current_seller).call[:report]
    end
  end
end
