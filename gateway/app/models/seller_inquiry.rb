# frozen_string_literal: true

# A seller asking for early access: the future Seller + Service rows, in one
# line, before sign-up exists. `price_atomic` is µUSDC.
class SellerInquiry < ApplicationRecord
  EMAIL = /\A[^@\s]+@[^@\s]+\z/

  validates :email, presence: true, format: { with: EMAIL }
  validates :service_name, presence: true, length: { maximum: 120 }
  validates :upstream_url, presence: true, format: { with: %r{\Ahttps?://\S+\z}, message: "must start with http:// or https://" }
  validates :price_atomic, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :notes, length: { maximum: 2000 }

  # For forms: the price as the user typed it, in USDC.
  attr_accessor :price_usdc
end
