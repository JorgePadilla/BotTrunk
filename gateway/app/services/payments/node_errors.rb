# frozen_string_literal: true

module Payments
  # Algorand's own error strings reach the payer verbatim through the
  # facilitator, and they are written for someone reading a node log, not for
  # an agent deciding what to do next. "asset 31566704 missing from 2DIN…" is
  # the node reporting a missing opt-in — accurate, and useless to a bot.
  #
  # Each rule turns one known string into an instruction. The original is kept
  # in the message: it is the source of truth, and clients may match on it.
  class NodeErrors
    RULES = [
      [ /must optin|asset (\d+) missing from/i,
        "The paying wallet is not opted in to USDC. Only the key holder can sign an ASA opt-in, so nobody can do it for you: " \
        "run `npx bottrunk-mcp wallet optin`, or make the opt-in the second transaction of an atomic group. " \
        "USDC sent to an account that has not opted in is rejected, not held." ],
      [ /below min|balance \d+ below/i,
        "The paying wallet is at its Algorand minimum balance. An account needs 0.1 ALGO to exist and 0.1 more per asset it holds, " \
        "so send it about 0.3 ALGO and leave the spare for fees." ],
      [ /overspend|underflow/i,
        "The paying wallet does not hold enough USDC for this call. Check the price in the 402 against its balance." ],
      [ /txn dead|round.*outside|lease/i,
        "The signed payment expired before it was submitted. Sign a fresh one — a payment is only valid for a short window of rounds." ],
      [ /already in ledger|duplicate/i,
        "This exact payment was already submitted. Do not re-sign it; check the transaction id on an explorer before paying again." ]
    ].freeze

    # explain("must optin, asset 31566704 missing from 2DIN…")
    #   => "The paying wallet is not opted in to USDC… (node said: must optin, …)"
    def self.explain(reason)
      raw = reason.to_s.strip
      return raw if raw.blank?

      hint = RULES.find { |pattern, _| raw.match?(pattern) }&.last
      hint ? "#{hint} (node said: #{raw})" : raw
    end
  end
end
