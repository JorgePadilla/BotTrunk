# frozen_string_literal: true

module Payments
  # Builds the payment requirements for one service: the `accepts` entry of the
  # 402 body. Pure — no HTTP, no chain access.
  class BuildRequirements
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
        description: @service.summary,
        mime_type: "application/json",
        extra: { decimals: net[:decimals], tag: @config.tag }
      )
      Result.success(requirements: requirements)
    end

    # The full 402 body: requirements + Bazaar discovery extension.
    def self.body_for(service:, requirements:)
      {
        x402Version: 2,
        error: "Payment required",
        accepts: [ requirements.to_h ],
        extensions: {
          bazaar: {
            info: {
              input: { type: "http", method: "POST",
                       params: service.inputs.to_h { |f| [ f.name, f.type ] } },
              output: { schema: { type: "object",
                                  properties: service.outputs.to_h { |f| [ f.name, { type: f.type, description: f.description } ] } } }
            }
          }
        }
      }
    end
  end
end
