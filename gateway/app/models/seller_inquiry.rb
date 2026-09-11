# frozen_string_literal: true

# A seller asking for early access: the future Seller + Service rows, in one
# line, before sign-up exists. `price_atomic` is µUSDC.
#
# Nothing a seller submits is listed automatically. An inquiry is a request,
# and it stays `pending` until a person approves or rejects it at
# /admin/inquiries — the record of that decision is the point of the status,
# because before it existed the decision only ever lived in a mailbox.
class SellerInquiry < ApplicationRecord
  EMAIL = /\A[^@\s]+@[^@\s]+\z/
  STATUSES = %w[pending approved rejected].freeze

  # A seller endpoint is proxied to, so the price has to be something a buyer
  # could plausibly pay. The ceiling is a sanity check, not a policy: anything
  # above it is a typo or a probe, and both deserve the same answer.
  MAX_PRICE_ATOMIC = 1_000_000_000_000 # 1,000,000 USDC per call

  validates :email, presence: true, format: { with: EMAIL }
  validates :service_name, presence: true, length: { maximum: 120 }
  validates :upstream_url, presence: true, format: { with: %r{\Ahttps?://\S+\z}, message: "must start with http:// or https://" }
  validates :price_atomic, presence: true,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_PRICE_ATOMIC,
                            message: "must be between 0.000001 and 1,000,000 USDC per call" }
  validates :notes, length: { maximum: 2000 }
  validates :status, inclusion: { in: STATUSES }
  validate :upstream_url_is_public

  scope :pending, -> { where(status: "pending").order(:created_at) }
  scope :reviewed, -> { where.not(status: "pending").order(reviewed_at: :desc) }

  # For forms: the price as the user typed it, in USDC.
  attr_accessor :price_usdc

  def pending? = status == "pending"

  def approve!(notes: nil) = review!("approved", notes)

  def reject!(notes: nil) = review!("rejected", notes)

  private

  def review!(to, notes)
    update!(status: to, reviewed_at: Time.current, review_notes: notes.presence || review_notes)
  end

  # An upstream URL is something we will one day make requests to on an agent's
  # behalf, so a private address here is the beginning of an SSRF, not a typo.
  # A host that does not resolve yet is allowed: sellers register endpoints
  # before they point DNS at them, and refusing that is worse than useless.
  def upstream_url_is_public
    return if upstream_url.blank?

    _uri, problem = Security::PublicUrl.parse(upstream_url, strict_dns: false)
    errors.add(:upstream_url, "must be a public address — this one resolves to a private network") if problem == :private
  end
end
