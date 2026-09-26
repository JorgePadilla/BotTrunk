# frozen_string_literal: true

module Fulfillers
  # Bitcoin delivered to an address, paid for in USDC — shaped exactly like the
  # lempira deposit: pay, get an order token, poll it, a person completes the
  # transfer and records the proof.
  #
  # It is `on_request` in the catalog and stays that way until a licensed
  # partner sits behind it, because exchanging one asset for another is a
  # regulated activity in every jurisdiction a buyer might call from. Answering
  # 503 before the payment header is read means nothing can be charged in the
  # meantime. See the note on `docs/deposits-hn.md` — the same reasoning, with
  # a bigger perimeter.
  #
  # What this class adds to HumanJob: an address that looks like an address,
  # and a quote frozen into the order at the moment it is taken, so the buyer
  # and the operator are looking at the same number afterwards.
  class BtcDelivery < HumanJob
    # Bech32 (bc1…), P2PKH (1…) and P2SH (3…). A regex is not a checksum, and
    # the operator verifies before sending — this only catches the typo that
    # would otherwise cost a person an hour.
    ADDRESS = /\A(bc1[02-9ac-hj-np-z]{11,71}|[13][1-9A-HJ-NP-Za-km-z]{25,34})\z/

    def call
      address = @input["btc_address"].to_s.strip
      return bad_request("btc_address does not look like a bitcoin address") unless address.match?(ADDRESS)

      @quote = Pricing::BtcDelivery.new(usdc: @service.usd_price)
      return no_price unless @quote.quotable?

      super
    end

    private

    # The quote is frozen into the order at the moment it is taken, so the
    # buyer polling later and the operator sending later are looking at the
    # same number — not at whatever the market did in between.
    def extra_params = { "quote" => @quote.to_quote }

    # No fresh price, no quote. Refusing costs the buyer nothing; guessing
    # would cost us the difference on every call.
    def no_price
      Result.success(status: 503, content_type: "application/json",
                     body: { error: "No bitcoin price fresh enough to quote on right now. Nothing was charged — try again in a few minutes." }.to_json)
    end
  end
end
