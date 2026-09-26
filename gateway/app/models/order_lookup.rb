# frozen_string_literal: true

# One token, two tables. An agent holding an order id should not have to know
# whether it bought a bank transfer or an afternoon of somebody's phone calls,
# so `GET /orders/:token` and the MCP order tool both come through here.
#
# Tokens are SecureRandom.base58(20), so a collision across tables is not a
# practical concern; deposits are checked first because there are more of them.
module OrderLookup
  MODELS = [ DepositOrder, WorkOrder ].freeze

  def self.find(token)
    token = token.to_s.strip
    return nil if token.blank?

    MODELS.lazy.filter_map { |model| model.find_by(token: token) }.first
  end
end
