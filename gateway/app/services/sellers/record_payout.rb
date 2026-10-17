# frozen_string_literal: true

module Sellers
  # Records USDC we already sent a seller by hand from the gateway wallet,
  # and tells them. The transfer itself happens in a wallet app: the server
  # never holds a key. Refused when it is more than they are owed, which
  # catches a misplaced decimal before it becomes the seller's balance.
  class RecordPayout
    def initialize(seller:, amount_usdc:, transaction_id:, notes: nil, now: Time.current)
      @seller = seller
      @amount_usdc = amount_usdc.to_s.strip
      @transaction_id = transaction_id
      @notes = notes.to_s.strip.presence
      @now = now
    end

    def call
      amount = atomic
      return Result.failure("Amount must be a number of USDC, like 12.50.", code: :invalid) if amount.nil? || amount <= 0
      return Result.failure("That is more than #{@seller.email} is owed (#{format_usdc(@seller.owed_atomic)}).", code: :over_owed) if amount > @seller.owed_atomic

      payout = @seller.payouts.new(amount: amount, transaction_id: @transaction_id, notes: @notes, paid_at: @now)
      return Result.failure(payout.errors.full_messages.to_sentence, code: :invalid) unless payout.save

      Notifications::Deliver.call(SellerMailer.with(payout: payout).payout_sent)
      Result.success(payout: payout)
    end

    private

    def atomic
      (BigDecimal(@amount_usdc) * 1_000_000).to_i
    rescue ArgumentError
      nil
    end

    def format_usdc(atomic) = ActionController::Base.helpers.number_to_currency(BigDecimal(atomic) / 1_000_000, precision: 2)
  end
end
