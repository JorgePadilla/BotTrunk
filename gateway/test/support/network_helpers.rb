# frozen_string_literal: true

# Turns Base and Solana on for one test, the way BASE_PAY_TO and
# SOLANA_PAY_TO do in production. Addresses are made-up but well-formed.
module NetworkHelpers
  BASE_PAY_TO = "0x1111111111111111111111111111111111111111"
  SOLANA_PAY_TO = "So1anaPayTo111111111111111111111111111111"

  def with_networks(base: BASE_PAY_TO, solana: SOLANA_PAY_TO)
    config = Rails.configuration.x402
    before = [ config.base_pay_to, config.solana_pay_to ]
    config.base_pay_to = base
    config.solana_pay_to = solana
    yield
  ensure
    config.base_pay_to, config.solana_pay_to = before
  end
end
