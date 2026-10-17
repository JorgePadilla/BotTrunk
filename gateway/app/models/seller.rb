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
  # Bump when /seller-terms changes in substance; sellers accept it again
  # before their next submission.
  TERMS_VERSION = "2026-10-18"
  MIN_PAYOUT_ATOMIC = 1_000_000 # 1 USDC

  has_many :listings, dependent: :restrict_with_error
  has_many :calls, dependent: :restrict_with_error
  has_many :payouts, dependent: :restrict_with_error

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

  def accepted_current_terms? = terms_version == TERMS_VERSION

  def accept_terms!(now: Time.current) = update!(terms_accepted_at: now, terms_version: TERMS_VERSION)

  # µUSDC. Earned is their share of every settled call; owed is what we have
  # not sent yet.
  def earned_atomic = calls.sum(:seller_amount)

  def paid_atomic = payouts.sum(:amount)

  def owed_atomic = earned_atomic - paid_atomic

  def rotate_signing_secret! = update!(signing_secret: self.class.new_secret)

  def self.new_secret = "bts_#{SecureRandom.base58(40)}"

  private

  def generate_signing_secret
    self.signing_secret ||= self.class.new_secret
  end
end
