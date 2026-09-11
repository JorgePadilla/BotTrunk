# frozen_string_literal: true

# Formatting for integer µUSDC (6 decimals). The ledger never stores floats;
# only views turn atomic units into "$0.005".
module MoneyHelper
  # usdc(5000) → "$0.005", usdc(5_000_000) → "$5.00", usdc(750) → "$0.00075".
  def usdc(atomic, decimals: nil)
    value = BigDecimal(atomic.to_i) / 1_000_000
    decimals ||= [ 2, value.to_s("F").split(".").last.sub(/0+\z/, "").length ].max
    "$#{format("%.#{decimals}f", value)}"
  end

  def short_address(address, head: 6, tail: 4)
    return "—" if address.blank?

    "#{address[0, head]}…#{address[-tail, tail]}"
  end
end
