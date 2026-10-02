# frozen_string_literal: true

module Payments
  # Builds the payment requirements for one service: the `accepts` entry of the
  # 402 body. Pure — no HTTP, no chain access.
  class BuildRequirements
    include MoneyHelper

    def initialize(service:, config: Rails.configuration.x402)
      @service = service
      @config = config
    end

    def call
      return Result.failure("payTo address is not configured", code: :not_configured) if @config.pay_to.blank?

      net = Networks.algorand(@config.network)
      requirements = Requirements.new(
        scheme: "exact",
        network: net[:caip2],
        asset: net[:usdc_asa],
        amount: @service.price_atomic,
        pay_to: @config.pay_to,
        max_timeout_seconds: @config.max_timeout_seconds,
        resource: "#{@config.public_host}/s/#{@service.slug}",
        description: listing_description,
        mime_type: "application/json",
        extra: { decimals: net[:decimals], tag: @config.tag, feePayer: @config.fee_payer }.compact
      )
      Result.success(requirements: requirements)
    end

    # What the Bazaar shows an agent deciding whether to call us. The one-line
    # summary read like a tagline next to listings that say what you get, what
    # it costs and that no signup is needed, so it is the full description plus
    # the price and the terms.
    def listing_description
      "#{@service.description} #{usdc(@service.price_atomic).delete_prefix('$')} USDC per call, " \
        "paid over x402 on Algorand. No account or API key; a call that fails is not charged."
    end

    # The full 402 body: requirements + Bazaar discovery extension, shaped
    # exactly like @x402/extensions' createBodyDiscoveryExtension (info +
    # a JSON Schema for it). The facilitator's catalog validator is strict:
    # `type` pinned by const, closed `input`, output with `type` + `example`.
    def self.body_for(service:, requirements:)
      {
        x402Version: 2,
        error: "Payment required",
        resource: requirements.resource_info,
        accepts: [ requirements.to_h ], # spec fields + resource fields kept for v1-style clients
        extensions: { bazaar: bazaar_extension(service) }
      }
    end

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
  end
end
