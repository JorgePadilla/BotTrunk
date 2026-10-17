# frozen_string_literal: true

# USDC we sent a seller, by hand, from the gateway wallet (Phase 1 pays out
# manually: the server never holds a key). Recorded after the transfer, with
# its Algorand transaction id, so the seller can check it on-chain. Amounts
# are µUSDC, like everything in the ledger.
class Payout < ApplicationRecord
  ALGORAND_TXID = /\A[A-Z2-7]{52}\z/

  belongs_to :seller

  normalizes :transaction_id, with: ->(id) { id.strip.upcase }

  validates :amount, numericality: { only_integer: true, greater_than: 0 }
  validates :transaction_id, presence: true, uniqueness: true, format: { with: ALGORAND_TXID, message: "must be a 52-character Algorand transaction id" }
  validates :paid_at, presence: true
end
