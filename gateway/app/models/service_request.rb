# frozen_string_literal: true

# A buyer asking for work we do not sell yet, or asking to arrange one of the
# `on_request` services. The demand side of the same queue `SellerInquiry`
# feeds: both are requests, both wait for a person, neither lists itself.
#
# `service_slug` is optional on purpose. A request that names a catalog entry
# is someone asking to arrange that service; a request with no slug is someone
# telling us what the catalog is missing, which is the more useful of the two.
class ServiceRequest < ApplicationRecord
  EMAIL = /\A[^@\s]+@[^@\s]+\z/
  STATUSES = %w[pending answered closed].freeze

  validates :email, presence: true, format: { with: EMAIL }
  validates :details, presence: true,
            length: { minimum: 20, maximum: 2000,
                      too_short: "needs a sentence or two — what the work is, and what a good answer looks like" }
  validates :budget_atomic, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }
  validate :service_slug_is_in_the_catalog

  scope :pending, -> { where(status: "pending").order(:created_at) }
  scope :reviewed, -> { where.not(status: "pending").order(reviewed_at: :desc) }

  # For forms: the budget as the user typed it, in USDC.
  attr_accessor :budget_usdc

  def pending? = status == "pending"

  # What they asked about, when they picked something we list.
  def service = service_slug.presence && Catalog::Service.find(service_slug)

  # A request naming nothing is the interesting kind: the catalog is missing it.
  def for_catalog_gap? = service_slug.blank?

  def answer!(notes: nil) = review!("answered", notes)

  def close!(notes: nil) = review!("closed", notes)

  private

  def review!(to, notes)
    update!(status: to, reviewed_at: Time.current, review_notes: notes.presence || review_notes)
  end

  # A slug that is not ours means a tampered form or a service we retired
  # between the page rendering and the submit. Neither should become a row
  # that the queue cannot make sense of.
  def service_slug_is_in_the_catalog
    return if service_slug.blank? || Catalog::Service.find(service_slug)

    errors.add(:service_slug, "is not a service we list")
  end
end
