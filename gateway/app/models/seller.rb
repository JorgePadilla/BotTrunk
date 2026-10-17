# frozen_string_literal: true

# Someone who sells an API through BotTrunk. Signs in with a link sent to
# their email; there is no password to store, leak or reset.
#
# `signing_secret` signs every request we forward to their API (B2), so they
# can refuse calls that did not come through the paywall. It is encrypted at
# rest and shown to them once.
class Seller < ApplicationRecord
  STATUSES = %w[active suspended].freeze
  ALGORAND_ADDRESS = /\A[A-Z2-7]{58}\z/
  SIGN_IN_LINK_TTL = 15.minutes

  encrypts :signing_secret

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :payout_address, with: ->(address) { address.strip.upcase.presence }

  validates :email, presence: true, uniqueness: true, format: { with: SellerInquiry::EMAIL }
  validates :name, length: { maximum: 120 }
  validates :payout_address, format: { with: ALGORAND_ADDRESS, message: "must be a 58-character Algorand address" }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }

  before_validation :generate_signing_secret, on: :create

  # The link works once: signing in moves `last_signed_in_at`, which changes
  # the token, so a link forwarded or found later is dead.
  generates_token_for :sign_in, expires_in: SIGN_IN_LINK_TTL do
    last_signed_in_at
  end

  def active? = status == "active"

  def rotate_signing_secret! = update!(signing_secret: self.class.new_secret)

  def self.new_secret = "bts_#{SecureRandom.base58(40)}"

  private

  def generate_signing_secret
    self.signing_secret ||= self.class.new_secret
  end
end
