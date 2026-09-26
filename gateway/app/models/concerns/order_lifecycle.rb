# frozen_string_literal: true

# The lifecycle every human-fulfilled order shares, extracted from DepositOrder
# when work orders arrived:
#
#   awaiting_payment  created by the fulfiller before the payment settles
#   pending           settled; in the queue for a person to do
#   delivered         done, with whatever proof the service promises
#   refunded          could not deliver; USDC sent back, refund txn recorded
#   cancelled         payment never settled (abandoned) — nothing owed
#
# `Gateway::HandlePaidCall` only ever calls `update!(status:)` and reads
# `token`, so anything including this drops into the paid loop unchanged.
module OrderLifecycle
  extend ActiveSupport::Concern

  STATUSES = %w[awaiting_payment pending delivered refunded cancelled].freeze
  OPEN = %w[pending].freeze
  DONE = %w[delivered refunded].freeze

  included do
    belongs_to :call, optional: true

    validates :token, :service_slug, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :price_atomic, numericality: { only_integer: true, greater_than: 0 }

    scope :queue, -> { where(status: OPEN).order(:created_at) }
    scope :done, -> { where(status: DONE).order(delivered_at: :desc, refunded_at: :desc) }
    scope :abandoned, -> { where(status: %w[awaiting_payment cancelled]).order(created_at: :desc) }
    scope :since, ->(time) { where(created_at: time..) }

    before_validation { self.token ||= SecureRandom.base58(20) }
  end

  def to_param = token

  def pending? = status == "pending"

  def open? = OPEN.include?(status)

  def paid_usdc = (BigDecimal(price_atomic) / 1_000_000).to_s("F")

  def refund!(transaction_id:, notes: nil)
    update!(status: "refunded", refund_transaction_id: transaction_id.to_s.strip, refunded_at: Time.current,
            notes: notes.presence || self.notes)
  end
end
