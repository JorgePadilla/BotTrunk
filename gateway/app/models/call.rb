# frozen_string_literal: true

# One paid call, as recorded after settlement. Money columns are integer
# atomic units of `asset` (µUSDC).
class Call < ApplicationRecord
  STATUSES = %w[settled].freeze

  validates :service_slug, :pay_to, :network, :asset, :status, presence: true
  validates :amount, :commission, :seller_amount, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }

  scope :since, ->(time) { where(created_at: time..) }

  # Paid by someone else's wallet: the number the Phase 1 milestone is about.
  # A call with no payer reported is left out, since nobody can say whose it was.
  scope :outside, -> { where.not(payer_address: [ nil, "", *own_payers ]) }

  def self.own_payers = Rails.configuration.x402.own_payers

  def own_payer? = self.class.own_payers.include?(payer_address)
end
