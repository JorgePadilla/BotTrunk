# frozen_string_literal: true

# One analytics event (see Analytics::Track). Settled payments are not events;
# they live in `calls`, which is the ledger. Everything here is best-effort
# telemetry and can be truncated without losing money.
class Event < ApplicationRecord
  NAMES = %w[page_view catalog_api mcp_call payment_required payment_rejected coming_soon].freeze
  CLIENTS = %w[bottrunk-mcp x402-client curl python node browser bot other].freeze

  validates :name, inclusion: { in: NAMES }
  validates :client, inclusion: { in: CLIENTS }

  scope :named, ->(name) { where(name: name) }
  scope :since, ->(time) { where(created_at: time..) }
end
