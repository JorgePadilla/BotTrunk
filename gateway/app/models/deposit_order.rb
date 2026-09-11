# frozen_string_literal: true

# One lempira deposit an agent paid for in USDC. Lifecycle:
#
#   awaiting_payment  created by the fulfiller before the payment settles
#   pending           settled; in the fulfilment queue (a person makes the bank transfer)
#   delivered         transfer done, receipt reference recorded
#   refunded          could not deliver; USDC sent back, refund txn recorded
#   cancelled         payment never settled (abandoned) — nothing owed
class DepositOrder < ApplicationRecord
  STATUSES = %w[awaiting_payment pending delivered refunded cancelled].freeze
  OPEN = %w[pending].freeze
  DONE = %w[delivered refunded].freeze

  belongs_to :call, optional: true

  encrypts :account_number, deterministic: true

  validates :token, :service_slug, :beneficiary_name, :account_number, :bank, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :amount_hnl, numericality: { only_integer: true, greater_than: 0 }
  validates :price_atomic, numericality: { only_integer: true, greater_than: 0 }
  validates :fee_bps, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :queue, -> { where(status: OPEN).order(:created_at) }
  scope :done, -> { where(status: DONE).order(delivered_at: :desc, refunded_at: :desc) }
  scope :abandoned, -> { where(status: %w[awaiting_payment cancelled]).order(created_at: :desc) }
  scope :since, ->(time) { where(created_at: time..) }

  before_validation { self.token ||= SecureRandom.base58(20) }

  def to_param = token

  def pending? = status == "pending"

  def open? = OPEN.include?(status)

  def deliver!(receipt_reference:, notes: nil)
    update!(status: "delivered", receipt_reference: receipt_reference.to_s.strip, delivered_at: Time.current, notes: notes.presence || self.notes)
  end

  def refund!(transaction_id:, notes: nil)
    update!(status: "refunded", refund_transaction_id: transaction_id.to_s.strip, refunded_at: Time.current, notes: notes.presence || self.notes)
  end

  # The public view an agent polls at GET /orders/:token. No bank details.
  def public_status
    {
      order_id: token, status: status, bank: bank, amount_hnl: amount_hnl, currency: "HNL",
      beneficiary_name: beneficiary_name, paid_usdc: (BigDecimal(price_atomic) / 1_000_000).to_s("F"),
      eta: (pending? ? "within 24 hours" : nil), delivered_at: delivered_at, receipt_reference: receipt_reference,
      refund_transaction_id: refund_transaction_id, created_at: created_at
    }.compact
  end
end
