# frozen_string_literal: true

# One paid call, as recorded after settlement. Money columns are integer
# atomic units of `asset` (µUSDC).
class Call < ApplicationRecord
  STATUSES = %w[settled].freeze

  validates :service_slug, :pay_to, :network, :asset, :status, presence: true
  validates :amount, :commission, :seller_amount, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }

  scope :since, ->(time) { where(created_at: time..) }
end
