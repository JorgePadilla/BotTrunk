# frozen_string_literal: true

# A seller's API on BotTrunk. Becomes a catalog entry (Catalog::Service) once
# a person has approved it, and from then on is listed, priced and paid for
# exactly like a built-in service; the paywall proxies to `upstream_url`.
#
#   draft ──submit──▶ pending ──approve──▶ live ──pause──▶ paused
#     ▲                  │                                   │
#     └──── edit ◀── rejected ◀──reject──┘    resubmit ◀─────┘
#
# The price cannot change once a listing has been live: the Bazaar freezes a
# resource's price at its first settlement, and a buyer's agent may have
# budgeted for it. A new price is a new listing.
class Listing < ApplicationRecord
  STATUSES = %w[draft pending live paused rejected].freeze
  EDITABLE = %w[draft rejected paused].freeze
  CATEGORIES = Catalog::Service::CATEGORIES - %w[Payments]
  FIELD_TYPES = %w[string integer number boolean object array].freeze
  SLUG = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  MAX_FIELDS = 30

  belongs_to :seller

  normalizes :slug, with: ->(slug) { slug.strip.downcase }
  normalizes :upstream_url, with: ->(url) { url.strip }

  validates :slug, presence: true, uniqueness: true, length: { in: 3..60 }, format: { with: SLUG, message: "may use only lowercase letters, digits and single dashes" }
  validates :name, presence: true, length: { maximum: 80 }
  validates :summary, presence: true, length: { maximum: 160 }
  validates :description, length: { maximum: 4_000 }
  validates :category, inclusion: { in: CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validates :upstream_url, presence: true, format: { with: %r{\Ahttps://\S+\z}, message: "must start with https://" }
  validates :price_atomic, numericality: { only_integer: true, greater_than_or_equal_to: SellerInquiry::MIN_PRICE_ATOMIC,
                                           less_than_or_equal_to: SellerInquiry::MAX_PRICE_ATOMIC,
                                           message: "must be between 0.01 and 1,000,000 USDC per call" }
  validate :slug_is_not_built_in
  validate :upstream_url_is_public, if: :upstream_url_changed?
  validate :price_is_frozen_once_live, on: :update
  validate :fields_are_well_formed

  scope :live, -> { where(status: "live") }
  scope :pending, -> { where(status: "pending").order(:submitted_at) }

  STATUSES.each { |s| define_method(:"#{s}?") { status == s } }

  def editable? = EDITABLE.include?(status)

  def price_usdc = BigDecimal(price_atomic.to_i) / 1_000_000

  def price_usdc=(value)
    self.price_atomic = (BigDecimal(value.to_s.strip) * 1_000_000).to_i
  rescue ArgumentError
    self.price_atomic = nil
  end

  # The form edits the schema as JSON text; a typo is a form error, not a 500.
  %i[inputs outputs].each do |attr|
    define_method(:"#{attr}_json") { JSON.pretty_generate(public_send(attr)) }
    define_method(:"#{attr}_json=") do |text|
      public_send(:"#{attr}=", JSON.parse(text.to_s))
    rescue JSON::ParserError
      @json_errors = (@json_errors || []) << attr
    end
  end

  def submit!(now: Time.current) = update!(status: "pending", submitted_at: now, review_notes: nil)

  def approve!(notes: nil, now: Time.current)
    update!(status: "live", reviewed_at: now, went_live_at: went_live_at || now, review_notes: notes.presence)
  end

  def reject!(notes: nil, now: Time.current) = update!(status: "rejected", reviewed_at: now, review_notes: notes.presence)

  def pause! = update!(status: "paused")

  # The catalog entry for this listing. Same shape as a built-in, so every
  # page, the 402, the Bazaar entry, the catalog API and the MCP tools treat
  # it the same way.
  def to_catalog_service
    Catalog::Service.new(
      slug: slug, name: name, summary: summary, description: description.presence || summary, category: category,
      provider: "Verified seller", price_usdc: price_usdc, upstream_url: upstream_url, seller_id: seller_id,
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: catalog_fields(inputs), outputs: catalog_fields(outputs)
    )
  end

  def self.catalog_services = Current.listing_services ||= live.order(:went_live_at).map(&:to_catalog_service)

  private

  def catalog_fields(list)
    Array(list).map { |f| Catalog::Field.new(f["name"].to_s, f["type"].to_s, f["description"].to_s, f["example"]) }
  end

  def slug_is_not_built_in
    errors.add(:slug, "is taken by a BotTrunk service") if Catalog::Service::SEED.any? { |s| s.slug == slug }
  end

  # The same rule as the seller inquiry: an upstream is a URL we will make
  # requests to on an agent's behalf, so a private address is an SSRF. It is
  # checked again on every call (Gateway::ProxyCall), because DNS can change.
  def upstream_url_is_public
    return if upstream_url.blank?

    _uri, problem = Security::PublicUrl.parse(upstream_url, strict_dns: false)
    errors.add(:upstream_url, "must be a public address — this one resolves to a private network") if problem == :private
  end

  def price_is_frozen_once_live
    errors.add(:price_atomic, "cannot change once the listing has been live; list it again at the new price") if went_live_at && price_atomic_changed?
  end

  def fields_are_well_formed
    Array(@json_errors).each { |attr| errors.add(attr, "is not valid JSON") }
    { inputs: inputs, outputs: outputs }.each do |attr, list|
      next errors.add(attr, "must be a list of fields") unless list.is_a?(Array)
      next errors.add(attr, "can have at most #{MAX_FIELDS} fields") if list.size > MAX_FIELDS

      list.each_with_index do |f, i|
        ok = f.is_a?(Hash) && f["name"].to_s.match?(/\A[A-Za-z_][A-Za-z0-9_]{0,63}\z/) && FIELD_TYPES.include?(f["type"]) && f["description"].to_s.length <= 500
        errors.add(attr, "field #{i + 1} needs a name (letters, digits, _), a type (#{FIELD_TYPES.join(', ')}) and a short description") unless ok
      end
    end
    errors.add(:inputs, "needs at least one field") if inputs.is_a?(Array) && inputs.empty?
  end
end
