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
  # could plausibly pay. The floor keeps the ledger honest — below a cent the
  # 15% commission rounds to nothing and the call is free to run and free to
  # abuse. The ceiling is a sanity check: above it is a typo or a probe, and
  # both deserve the same answer.
  MIN_PRICE_ATOMIC = 10_000            # 0.01 USDC per call
  MAX_PRICE_ATOMIC = 1_000_000_000_000 # 1,000,000 USDC per call

  validates :email, presence: true, format: { with: EMAIL }
  validates :service_name, presence: true, length: { maximum: 120 }
  validates :upstream_url, presence: true, format: { with: %r{\Ahttps?://\S+\z}, message: "must start with http:// or https://" }
  validates :notes, length: { maximum: 2000 }
  validates :status, inclusion: { in: STATUSES }
  # Covers both an empty box and something we could not read as a number —
  # "1,50" parses to nothing, and "can't be blank" is a baffling answer to it.
  validates :price_atomic, presence: { message: "must be a number in USDC, like 0.05" }

  # These two run only when the value they judge is being set, so tightening a
  # rule never makes an existing row unreviewable. A row submitted under the
  # old limits still has to be approved or rejected by a person, and failing
  # that update with "price must be between…" would leave it stuck in the
  # queue forever with no way out — which is exactly what happened the first
  # time these limits landed.
  validates :price_atomic,
            numericality: { only_integer: true, greater_than_or_equal_to: MIN_PRICE_ATOMIC, less_than_or_equal_to: MAX_PRICE_ATOMIC,
                            message: "must be between 0.01 and 1,000,000 USDC per call" },
            if: :price_atomic_changed?
  validate :upstream_url_is_public, if: :upstream_url_changed?

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
