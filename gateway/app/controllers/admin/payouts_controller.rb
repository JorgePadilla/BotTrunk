# frozen_string_literal: true

module Admin
  # What each seller is owed, and the payouts we have sent. Send the USDC
  # from the gateway wallet first, then record it here with the transaction
  # id; the seller is emailed a link to it.
  class PayoutsController < BaseController
    def index
      @sellers = Seller.joins(:calls).distinct.includes(:payouts).sort_by { |s| -s.owed_atomic }
      @recent = Payout.includes(:seller).order(paid_at: :desc).limit(50)
      # Sellers are paid on Algorand; USDC taken on Base or Solana lands in
      # those wallets and has to be moved by hand when Algorand runs short.
      @received = Call.group(:network).sum(:amount)
    end

    def create
      seller = Seller.find(params[:seller_id])
      result = Sellers::RecordPayout.new(seller: seller, amount_usdc: params[:amount_usdc], transaction_id: params[:transaction_id], notes: params[:notes]).call
      if result.success?
        redirect_to admin_payouts_path, notice: "Recorded #{helpers.usdc(result[:payout].amount)} to #{seller.email}. They were emailed."
      else
        redirect_to admin_payouts_path, alert: result.error
      end
    end
  end
end
