# frozen_string_literal: true

module Mcp
  # The tools the hosted MCP endpoint exposes. All of them are free and
  # read-only: a remote server cannot hold an agent's wallet, so it can answer
  # "what is there, what does it cost, where is my order" but never spend.
  # Paying is done by the agent itself — with `bottrunk-mcp` on its own
  # machine, or by calling the endpoint and answering the 402 directly, which
  # `bottrunk_payment_instructions` spells out.
  class Tools
    Tool = Data.define(:name, :description, :schema, :handler)

    def self.all = DEFINITIONS

    def self.list = DEFINITIONS.map { |t| { name: t.name, description: t.description, inputSchema: t.schema } }

    def self.find(name) = DEFINITIONS.find { |t| t.name == name }

    # Runs a tool and returns an MCP tool result. A tool that refuses (bad
    # input, unknown slug) answers with isError so the agent can correct
    # itself instead of the whole call failing.
    def self.call(name, arguments)
      tool = find(name) or return error("Unknown tool #{name}. Call tools/list to see what exists.")

      new(arguments || {}).public_send(tool.handler)
    rescue StandardError => e
      Rails.logger.error("mcp: #{name} failed: #{e.class}: #{e.message}")
      error("#{name} failed: #{e.message}")
    end

    def self.text(payload)
      body = payload.is_a?(String) ? payload : JSON.pretty_generate(payload)
      { content: [ { type: "text", text: body } ], isError: false }
    end

    def self.error(message) = { content: [ { type: "text", text: message } ], isError: true }

    def initialize(arguments)
      @arguments = arguments.is_a?(Hash) ? arguments.with_indifferent_access : {}.with_indifferent_access
    end

    def catalog
      services = Catalog::Service.all
      if (category = @arguments[:category].presence)
        services = services.select { |s| s.category.casecmp?(category) }
      end
      if (query = @arguments[:query].presence)
        services = services.select { |s| s.matches?(query) }
      end
      return self.class.error("No service matches that. Call bottrunk_catalog with no arguments to see everything.") if services.empty?

      self.class.text(
        services: services.map { |s| summary_for(s) },
        note: "Prices are USDC per call. Deposit tiers reprice from the day's Banco Central de Honduras reference rate. " \
              "Call bottrunk_payment_instructions with a slug to learn how to pay for one."
      )
    end

    def service
      svc = lookup or return self.class.error(unknown_slug)

      self.class.text(
        summary_for(svc).merge(
          description: svc.description,
          inputs: svc.inputs.map { |f| { name: f.name, type: f.type, description: f.description, example: f.example }.compact },
          outputs: svc.outputs.map { |f| { name: f.name, type: f.type, description: f.description }.compact },
          example_request: { method: "POST", url: svc.endpoint_url, body: svc.example_body },
          how_to_pay: how_to_pay(svc)
        )
      )
    end

    def payment_instructions
      svc = lookup or return self.class.error(unknown_slug)
      return self.class.error("#{svc.name} is not callable yet (status #{svc.status}). Write to hello@bottrunk.com to arrange it.") unless svc.live?

      built = Payments::BuildRequirements.new(service: svc).call
      return self.class.error("Payment requirements are unavailable right now.") if built.failure?

      requirements = built[:requirements]
      self.class.text(
        slug: svc.slug,
        endpoint: svc.endpoint_url,
        price_usdc: format("%.6f", svc.usd_price),
        payment_requirements: requirements.to_h,
        steps: [
          "POST the JSON body to the endpoint with no payment header. You get HTTP 402 with these requirements.",
          "Sign an Algorand transfer of `amount` (atomic units, 6 decimals) of asset `asset` to `payTo` on `network`.",
          "Wrap it in an x402 v2 PaymentPayload — see `payload_shape` below — and base64 the JSON.",
          "Retry the same POST with header PAYMENT-SIGNATURE: <that base64>. X-PAYMENT is accepted as an alias.",
          "You get 200 with the result and a PAYMENT-RESPONSE header carrying the on-chain transaction id."
        ],
        payload_shape: {
          x402Version: 2,
          accepted: "the entry from accepts[] you are paying — exactly as given above, scheme and network included",
          payload: { paymentGroup: [ "<base64 msgpack of each signed transaction>" ], paymentIndex: "index of your transfer in paymentGroup; 0 for a plain single transfer" },
          resource: { url: svc.endpoint_url }
        },
        payload_note: "In v2 the scheme and network live inside `accepted`, not at the top level. The v1 flat shape is still accepted. " \
                      "Full worked example: https://bottrunk.com/docs#payment",
        easier: "Run `npx bottrunk-mcp` on the machine your agent controls — it creates a wallet, answers 402s and enforces your spending caps. Setup for twelve clients: https://bottrunk.com/connect",
        facilitator: Rails.configuration.x402.facilitator_url,
        algo_required: "Build the transfer as an atomic group with extra.feePayer and the facilitator covers the network fee, so the call itself costs you USDC only; " \
                       "sign a plain transfer instead and you pay its ~0.001 ALGO yourself. Either way the paying account must be opted in to the USDC asset, " \
                       "which needs about 0.1 ALGO of Algorand minimum balance. Budget ~0.2 ALGO once, then USDC per call."
      )
    end

    def quote_deposit
      amount = @arguments[:amount_hnl].to_i
      tiers = Catalog::Service.all.select(&:lempira?)
      tier = tiers.find { |t| t.price_hnl == amount }
      unless tier
        return self.class.error("Deposits are sold in fixed amounts: #{tiers.map { |t| "L#{t.price_hnl}" }.join(', ')}. " \
                                "Ask for one of those, or write to hello@bottrunk.com for another amount.")
      end

      pricing = Pricing::LempiraDeposit.new(amount_hnl: amount)
      rate = Rates::UsdHnl.info
      self.class.text(
        slug: tier.slug,
        endpoint: tier.endpoint_url,
        amount_hnl: amount,
        price_usdc: format("%.6f", pricing.price_usdc),
        price_atomic: pricing.price_atomic.to_s,
        rate: {
          reference: rate.rate.to_s("F"), source: rate.source, as_of: rate.as_of,
          spread_hnl: Pricing::LempiraDeposit.spread.to_s("F"),
          buyer_rate: pricing.effective_rate.to_s("F"),
          fee_percent: (pricing.fee_bps / 100.0)
        },
        delivery: "A person makes the transfer to the beneficiary's BAC Credomatic account in Honduras within 24 hours and returns the bank receipt reference.",
        required_input: { beneficiary_name: "string", account_number: "digits only" },
        note: "The price moves with the reference rate; the 402 at the moment you pay is authoritative."
      )
    end

    def order_status
      token = @arguments[:order_id].to_s.strip
      return self.class.error("order_id is required — it is the token a paid, human-fulfilled call returned.") if token.blank?

      order = OrderLookup.find(token)
      return self.class.error("No order with that id. Ids look like `8kPz3n…` and come from the response of a paid deposit or work call.") unless order

      self.class.text(order.public_status)
    end

    private

    def lookup = Catalog::Service.find(@arguments[:slug].to_s.strip)

    def unknown_slug
      "No service with slug `#{@arguments[:slug]}`. Call bottrunk_catalog to see the slugs."
    end

    def summary_for(svc)
      {
        slug: svc.slug, name: svc.name, category: svc.category, provider: svc.provider,
        status: svc.status, endpoint: svc.endpoint_url, summary: svc.summary,
        price_usdc: format("%.6f", svc.usd_price), price_atomic: svc.price_atomic.to_s,
        amount_hnl: svc.price_hnl, tool_in_bottrunk_mcp: (svc.tool_name if svc.live?)
      }.compact
    end

    def how_to_pay(svc)
      return "Not callable yet (status #{svc.status}). Write to hello@bottrunk.com to arrange it." unless svc.live?

      "Call bottrunk_payment_instructions with this slug, or run `npx bottrunk-mcp` locally and use the tool #{svc.tool_name}."
    end

    DEFINITIONS = [
      Tool.new(
        name: "bottrunk_catalog", handler: :catalog,
        description: "Everything an agent can buy on BotTrunk, priced in USDC per call: data utilities, and work a person does in the real world — such as putting money into someone's bank account and returning the receipt. Free to call. Returns slug, price, status and endpoint for each service.",
        schema: {
          type: "object",
          properties: {
            query: { type: "string", description: "Optional text to match against name, summary and category." },
            category: { type: "string", description: "Optional exact category: Payments, Data, Verification, Translation or Procurement." }
          },
          additionalProperties: false
        }
      ),
      Tool.new(
        name: "bottrunk_service", handler: :service,
        description: "Everything about one BotTrunk service: full description, input and output schema, an example request body, the live price and how to pay for it. Free to call.",
        schema: {
          type: "object",
          properties: { slug: { type: "string", description: "Service slug, e.g. scrape-markdown or deposit-bac-1000." } },
          required: [ "slug" ], additionalProperties: false
        }
      ),
      Tool.new(
        name: "bottrunk_payment_instructions", handler: :payment_instructions,
        description: "The exact x402 payment requirements for a service — amount in atomic USDC, asset, network and payTo address — plus the four steps to pay it. Use this when your agent has its own Algorand wallet and wants to pay the endpoint directly. Free to call.",
        schema: {
          type: "object",
          properties: { slug: { type: "string", description: "Service slug to be paid." } },
          required: [ "slug" ], additionalProperties: false
        }
      ),
      Tool.new(
        name: "bottrunk_quote_deposit", handler: :quote_deposit,
        description: "What it costs in USDC, right now, to put money in a person's bank account: the day's reference rate, the spread, the fee and the final price. The live corridor is Honduras — lempiras into a BAC Credomatic account, priced from the Banco Central de Honduras rate. Free to call.",
        schema: {
          type: "object",
          properties: { amount_hnl: { type: "integer", description: "Lempiras to deliver: 1000, 2500, 5000 or 10000." } },
          required: [ "amount_hnl" ], additionalProperties: false
        }
      ),
      Tool.new(
        name: "bottrunk_order_status", handler: :order_status,
        description: "Status of an order a person has to fulfil, such as a bank deposit: pending, delivered with the bank receipt reference, or refunded with the transaction id. Free to call.",
        schema: {
          type: "object",
          properties: { order_id: { type: "string", description: "The order token returned when the deposit was paid." } },
          required: [ "order_id" ], additionalProperties: false
        }
      )
    ].freeze
  end
end
