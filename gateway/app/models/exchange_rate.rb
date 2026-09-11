# frozen_string_literal: true

# A stored USD→HNL reference rate (see Rates::UsdHnl). Sources: "bch" (Banco
# Central de Honduras Web API), "feed" (open.er-api.com), "manual" (HNL_PER_USD).
class ExchangeRate < ApplicationRecord
  SOURCES = %w[bch feed manual].freeze

  validates :pair, :source, :as_of, :fetched_at, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :rate, numericality: { greater_than: 0 }

  scope :usd_hnl, -> { where(pair: "USD/HNL") }
  scope :newest_first, -> { order(fetched_at: :desc) }
end
