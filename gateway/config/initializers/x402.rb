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
  # Base and Solana are offered only once their receiving address is set, so
  # a deploy without them changes nothing. Public addresses, not keys
  # (docs/x402-algorand.md, "Base and Solana"). A malformed one stops boot
  # rather than publishing a 402 nobody can pay.
  config.x402.base_pay_to = ENV["BASE_PAY_TO"].presence&.strip
  config.x402.solana_pay_to = ENV["SOLANA_PAY_TO"].presence&.strip
  if config.x402.base_pay_to && !config.x402.base_pay_to.match?(/\A0x[0-9a-fA-F]{40}\z/)
    raise ArgumentError, "BASE_PAY_TO must be a 0x address (42 characters)"
  end
  if config.x402.solana_pay_to && !config.x402.solana_pay_to.match?(/\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/)
    raise ArgumentError, "SOLANA_PAY_TO must be a Solana address (base58, 32-44 characters)"
  end
  config.x402.commission_bps = 1500 # 15% of every call, in basis points
  config.x402.adapter = "Payments::Adapters::Facilitator"
  config.x402.public_host = ENV.fetch("BOTTRUNK_PUBLIC_HOST", "https://api.bottrunk.com")
  # Wallets that are ours: the test payer `bin/pay` signs with, the "bank" that
  # funds it, and whatever OWN_PAYER_ADDRESSES adds (our own agents). Their
  # calls are real money but not traction, so Stats counts them apart.
  # Addresses are public; nothing here is a secret.
  config.x402.own_payers = [
    "LQAWG3WUMKWTFGEFCCOET6JGPRKD2JFYPIJ6HPIRYAC6QDUJSBDVMCKPFQ",
    "ABEAGNREVBDSINTSOWXYXOANZDRTLBWDGULA3SALTWRMXNEED2LWZNSADE",
    *ENV.fetch("OWN_PAYER_ADDRESSES", "").split(",").map(&:strip)
  ].compact_blank.uniq.freeze
end
