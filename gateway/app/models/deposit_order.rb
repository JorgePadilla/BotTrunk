# frozen_string_literal: true

# One lempira deposit an agent paid for in USDC. The lifecycle it shares with
# every other human-fulfilled order lives in OrderLifecycle; what is left here
# is what makes a deposit a deposit — a bank, an account and an amount.
class DepositOrder < ApplicationRecord
  include OrderLifecycle

  STATUSES = OrderLifecycle::STATUSES
  OPEN = OrderLifecycle::OPEN
  DONE = OrderLifecycle::DONE

  encrypts :account_number, deterministic: true

  validates :beneficiary_name, :account_number, :bank, presence: true
  validates :amount_hnl, numericality: { only_integer: true, greater_than: 0 }
  validates :fee_bps, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def deliver!(receipt_reference:, notes: nil)
    update!(status: "delivered", receipt_reference: receipt_reference.to_s.strip, delivered_at: Time.current, notes: notes.presence || self.notes)
  end


  # The public view an agent polls at GET /orders/:token. No bank details.
  def public_status
    {
      order_id: token, status: status, bank: bank, amount_hnl: amount_hnl, currency: "HNL",
      beneficiary_name: beneficiary_name, paid_usdc: paid_usdc,
      eta: (pending? ? "within 24 hours" : nil), delivered_at: delivered_at, receipt_reference: receipt_reference,
      refund_transaction_id: refund_transaction_id, created_at: created_at
    }.compact
  end
end
