# x402 settings for the gateway. Protocol facts live in docs/x402-algorand.md;
# secrets (the receiving address) live in Rails credentials under `algorand:`.
#
#   algorand:
#     pay_to: <58-char address>
#     network: testnet   # or mainnet
Rails.application.configure do
  creds = Rails.application.credentials.algorand || {}

  config.x402 = ActiveSupport::OrderedOptions.new
  config.x402.facilitator_url = ENV.fetch("X402_FACILITATOR_URL", "https://facilitator.goplausible.xyz")
  config.x402.network = (ENV["ALGORAND_NETWORK"] || creds[:network] || "testnet").to_sym
  config.x402.pay_to = ENV["ALGORAND_PAY_TO"] || creds[:pay_to]
  config.x402.max_timeout_seconds = 60
  config.x402.tag = "x402-global-challenge"
  # The facilitator's fee-payer account (GET /supported → kinds[].extra.feePayer for algorand:*).
  # Advertising it lets x402 clients build gasless payments; the facilitator co-signs and pays fees.
  config.x402.fee_payer = ENV.fetch("X402_FEE_PAYER", "ZMFK2OI7ZBD2U27ISERZC4S6LKM6WMFJPZQ4MYNJDZ2VNBNMBA67RA22AA")
  config.x402.commission_bps = 1500 # 15% of every call, in basis points
  config.x402.adapter = "Payments::Adapters::Algorand"
  config.x402.public_host = ENV.fetch("BOTTRUNK_PUBLIC_HOST", "https://api.bottrunk.com")
end
