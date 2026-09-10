# frozen_string_literal: true

module Payments
  # Algorand network ids and the USDC ASA on each. Values from docs/x402-algorand.md.
  module Networks
    ALGORAND = {
      mainnet: { caip2: "algorand:wGHE2Pwdvd7S12BL5FaOP20EGYesN73ktiC1qzkkit8=", usdc_asa: "31566704", decimals: 6 },
      testnet: { caip2: "algorand:SGO1GKSzyE7IEPItTxCByw9x8FmnrCDexi9/cOUJOiI=", usdc_asa: "10458941", decimals: 6 }
    }.freeze

    def self.algorand(name) = ALGORAND.fetch(name.to_sym)
  end
end
