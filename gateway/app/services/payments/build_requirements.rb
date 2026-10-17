# frozen_string_literal: true

module Payments
  # Builds the payment requirements for one service: the `accepts` entries of
  # the 402 body, one per network we take USDC on. Algorand always, first;
  # Base and Solana once their receiving address is configured. Pure — no
  # HTTP, no chain access.
  class BuildRequirements
    include MoneyHelper

    # Merchant identity for the facilitator's catalog, GoPlausible's
    # `x402-merchant` extension (docs/x402-algorand.md). Without it BotTrunk is
    # a bare address in /discovery/merchants with no categories, and the guide
    # calls it the only way to set them. Clients copy `extensions` into the
    # payment payload, so it reaches the facilitator the same way as `bazaar`.
    MERCHANT = {
      info: {
        name: "BotTrunk",
        website: "https://bottrunk.com",
        logo: "https://bottrunk.com/icon.png",
        categories: [ "web data", "developer tools", "human services", "payments", "algorand", "base", "solana" ]
      },
      schema: {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        type: "object",
        required: %w[name],
        properties: {
          name: { type: "string" },
          website: { type: "string" },
          logo: { type: "string" },
          categories: { type: "array", items: { type: "string" } }
        }
      }
    }.freeze

    def initialize(service:, config: Rails.configuration.x402)
      @service = service
      @config = config
    end

    # `accepts` is every option, in the order the 402 lists them;
    # `requirements` is the first (Algorand), for callers that show one.
    def call
      return Result.failure("payTo address is not configured", code: :not_configured) if @config.pay_to.blank?

      accepts = Networks.offered(@config).each_with_index.map do |net, i|
        # Algorand's extra keeps the field order it has always had.
        extra = i.zero? ? { decimals: net[:decimals], tag: @config.tag, **net[:extra] } : { tag: @config.tag, **net[:extra] }
        option(net[:id], net[:asset], net[:pay_to], extra)
      end
      Result.success(accepts: accepts, requirements: accepts.first)
    end

    # The networks this gateway takes, by name, for messages and pages.
    def self.network_names(config = Rails.configuration.x402) = Networks.offered(config).map { |n| n[:name].sub(" TestNet", "").sub(" Sepolia", "").sub(" devnet", "") }

    # What the Bazaar shows an agent deciding whether to call us. The one-line
    # summary read like a tagline next to listings that say what you get, what
    # it costs and that no signup is needed, so it is the full description plus
    # the price and the terms.
    def listing_description
      "#{@service.description} #{usdc(@service.price_atomic).delete_prefix('$')} USDC per call, " \
        "paid over x402 on #{self.class.network_names(@config).to_sentence(last_word_connector: ' or ', two_words_connector: ' or ')}. " \
        "No account or API key; a call that fails is not charged."
    end

    # The full 402 body: requirements + Bazaar discovery extension, shaped
    # exactly like @x402/extensions' createBodyDiscoveryExtension (info +
    # a JSON Schema for it). The facilitator's catalog validator is strict:
    # `type` pinned by const, closed `input`, output with `type` + `example`.
    def self.body_for(service:, requirements:)
      options = Array(requirements)
      {
        x402Version: 2,
        error: "Payment required",
        resource: options.first.resource_info,
        accepts: options.map(&:to_h), # spec fields + resource fields kept for v1-style clients
        extensions: extensions_for(service)
      }
    end

    # Everything the 402 advertises beyond the requirements, and what the
    # gateway hands the facilitator on verify and settle.
    def self.extensions_for(service) = { bazaar: bazaar_extension(service), "x402-merchant": MERCHANT }

    def self.bazaar_extension(service)
      # Only inputs that carry a real example. Filling the rest with placeholders
      # gave agents a body they could copy that was refused (a "…" selector, a
      # deprecated flag).
      input_example  = service.example_body
      input_schema   = { type: "object", properties: service.inputs.to_h { |f| [ f.name, f.json_schema ] } }
      output_example = service.outputs.to_h { |f| [ f.name, f.example_value ] }
      output_schema  = { properties: service.outputs.to_h { |f| [ f.name, f.json_schema ] } }

      {
        info: {
          input: { type: "http", method: "POST", bodyType: "json", body: input_example },
          output: { type: "json", example: output_example }
        },
        schema: {
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          type: "object",
          properties: {
            input: {
              type: "object",
              properties: {
                type: { type: "string", const: "http" },
                method: { type: "string", enum: %w[POST PUT PATCH] },
                bodyType: { type: "string", enum: %w[json form-data text] },
                body: input_schema,
                pathParams: { type: "object" }
              },
              required: %w[type method bodyType body],
              additionalProperties: false
            },
            output: {
              type: "object",
              properties: { type: { type: "string" }, example: { type: "object" }.merge(output_schema) },
              required: %w[type]
            }
          },
          required: %w[input]
        }
      }
    end

    private

    def option(network, asset, pay_to, extra)
      Requirements.new(
        scheme: "exact", network: network, asset: asset, amount: @service.price_atomic, pay_to: pay_to,
        max_timeout_seconds: @config.max_timeout_seconds, resource: "#{@config.public_host}/s/#{@service.slug}",
        description: listing_description, mime_type: "application/json", extra: extra.compact
      )
    end
  end
end
