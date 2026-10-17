# frozen_string_literal: true

module Payments
  module Adapters
    # The facilitator client's old name, from when Algorand was the only
    # network. Kept so an ALGORAND-era config value still resolves.
    Algorand = Facilitator
  end
end
