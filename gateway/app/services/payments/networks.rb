# frozen_string_literal: true

module Payments
  # The networks we take USDC on, their ids and the USDC asset on each.
  # Values from docs/x402-algorand.md ("Networks and assets").
  module Networks
    ALGORAND = {
      mainnet: { caip2: "algorand:wGHE2Pwdvd7S12BL5FaOP20EGYesN73ktiC1qzkkit8=", usdc_asa: "31566704", decimals: 6 },
      testnet: { caip2: "algorand:SGO1GKSzyE7IEPItTxCByw9x8FmnrCDexi9/cOUJOiI=", usdc_asa: "10458941", decimals: 6 }
    }.freeze

    BASE = {
      mainnet: { caip2: "eip155:8453", usdc: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", decimals: 6, extra: { name: "USD Coin", version: "2" } },
      testnet: { caip2: "eip155:84532", usdc: "0x036CbD53842c5426634e7929541eC2318f3dCF7e", decimals: 6, extra: { name: "USDC", version: "2" } }
    }.freeze

    SOLANA_FEE_PAYER = "8a8fFNfk2AGS7rgVv1BoqPUWnzQuoCrShJV8tSE6RAYi"
    SOLANA = {
      mainnet: { caip2: "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp", usdc: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", decimals: 6, extra: { feePayer: SOLANA_FEE_PAYER } },
      testnet: { caip2: "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1", usdc: "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU", decimals: 6, extra: { feePayer: SOLANA_FEE_PAYER } }
    }.freeze

    EVM_ADDRESS = /\A0x[0-9a-fA-F]{40}\z/
    SOLANA_ADDRESS = /\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/

    # Human names for a CAIP-2 id, for stats and messages.
    NAMES = {
      "eip155:8453" => "Base", "eip155:84532" => "Base Sepolia",
      "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp" => "Solana", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1" => "Solana devnet",
      ALGORAND[:mainnet][:caip2] => "Algorand", ALGORAND[:testnet][:caip2] => "Algorand TestNet"
    }.freeze

    def self.algorand(name) = ALGORAND.fetch(name.to_sym)

    def self.base(name) = BASE.fetch(name.to_sym)

    def self.solana(name) = SOLANA.fetch(name.to_sym)

    def self.name_for(caip2) = NAMES.fetch(caip2.to_s, caip2.to_s)

    # Every network this gateway takes USDC on right now, Algorand first:
    # [{ id:, name:, asset:, pay_to:, decimals:, extra: }]. Base and Solana
    # only once their receiving address is configured.
    def self.offered(config = Rails.configuration.x402)
      algorand = algorand(config.network)
      list = [ { id: algorand[:caip2], name: name_for(algorand[:caip2]), asset: algorand[:usdc_asa], pay_to: config.pay_to,
                 decimals: algorand[:decimals], extra: { feePayer: config.fee_payer } } ]
      { base: config.base_pay_to, solana: config.solana_pay_to }.each do |chain, pay_to|
        next if pay_to.blank?

        net = public_send(chain, config.network)
        list << { id: net[:caip2], name: name_for(net[:caip2]), asset: net[:usdc], pay_to: pay_to, decimals: net[:decimals], extra: net[:extra] }
      end
      list
    end
  end
end
