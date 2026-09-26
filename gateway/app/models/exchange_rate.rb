# frozen_string_literal: true

# A stored reference rate, one row per fetch.
#
# USD→HNL (see Rates::UsdHnl) from "bch" (Banco Central de Honduras Web API),
# "feed" (open.er-api.com) or "manual" (HNL_PER_USD); USD→BTC (Rates::UsdBtc)
# from "coinbase". The pair is part of the row rather than the table, so a new
# pair is a new source in this list and nothing else.
class ExchangeRate < ApplicationRecord
  SOURCES = %w[bch feed manual coinbase].freeze

  validates :pair, :source, :as_of, :fetched_at, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :rate, numericality: { greater_than: 0 }

  scope :usd_hnl, -> { where(pair: "USD/HNL") }
  scope :usd_btc, -> { where(pair: "USD/BTC") }
  scope :newest_first, -> { order(fetched_at: :desc) }
end
