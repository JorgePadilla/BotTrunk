# frozen_string_literal: true

# One observation of what something costs in Honduras, made by a person.
#
# Rows are never updated — a new week is a new row. `latest` is what the paid
# service sells; the history behind it is what makes the latest believable.
class LocalPrice < ApplicationRecord
  STALE_AFTER = 21.days

  validates :item, :unit, :city, :source, presence: true
  validates :price_hnl, numericality: { greater_than: 0 }
  validates :observed_at, presence: true
  validate :not_from_the_future

  scope :recent, -> { order(observed_at: :desc, created_at: :desc) }
  scope :for_city, ->(city) { where(city: city) if city.present? }
  scope :for_items, ->(items) { where(item: items) if items.present? }

  # The newest observation of each item in each city, in one query. Postgres
  # requires the DISTINCT ON columns to lead the ORDER BY, so this cannot
  # reuse `recent` — it is the same intent with the ordering it demands, and
  # the result is wrapped as a subquery so callers can order it as they like.
  def self.latest
    newest = select("DISTINCT ON (item, city) *").order(:item, :city, observed_at: :desc, created_at: :desc)
    from(newest.arel.as(table_name))
  end

  def stale? = observed_at < STALE_AFTER.ago.to_date

  def days_old = (Date.current - observed_at).to_i

  def to_reading(rate)
    {
      item: item, unit: unit, city: city,
      price_hnl: price_hnl.to_s("F"),
      price_usd: rate ? (price_hnl / rate).round(4).to_s("F") : nil,
      observed_at: observed_at.iso8601,
      days_old: days_old,
      stale: stale?,
      source: source,
      notes: notes.presence
    }.compact
  end

  private

  def not_from_the_future
    errors.add(:observed_at, "cannot be in the future") if observed_at.present? && observed_at > Date.current
  end
end
