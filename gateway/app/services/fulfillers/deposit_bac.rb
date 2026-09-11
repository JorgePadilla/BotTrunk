# frozen_string_literal: true

module Fulfillers
  # Built-in, human-fulfilled service: an agent pays USDC, a person deposits
  # lempiras into a BAC Credomatic account within 24 hours. This fulfiller
  # only validates the request and opens the order; the money side is the
  # normal x402 loop and the bank side is the admin queue (/admin/orders).
  #
  # Runs before settlement, so the order starts as `awaiting_payment`;
  # Gateway::HandlePaidCall flips it to `pending` once the USDC has settled
  # and links the Call row.
  class DepositBac
    ACCOUNT = /\A\d{6,20}\z/
    MAX_ORDERS_PER_ACCOUNT_PER_DAY = 3

    def initialize(input:, service:)
      @input = input.is_a?(Hash) ? input : {}
      @service = service
    end

    def call
      name = @input["beneficiary_name"].to_s.squish
      account = @input["account_number"].to_s.gsub(/[\s-]/, "")
      concept = @input["concept"].to_s.squish.presence
      email = @input["contact_email"].to_s.strip.presence

      return bad_request("beneficiary_name is required (2–80 characters)") unless name.length.between?(2, 80)
      return bad_request("account_number must be 6–20 digits") unless account.match?(ACCOUNT)
      return bad_request("concept is at most 60 characters") if concept && concept.length > 60
      return bad_request("contact_email is not a valid email") if email && !email.match?(URI::MailTo::EMAIL_REGEXP)
      return limit_reached if DepositOrder.where(account_number: account, status: %w[pending delivered]).since(24.hours.ago).count >= MAX_ORDERS_PER_ACCOUNT_PER_DAY

      pricing = Pricing::LempiraDeposit.new(amount_hnl: @service.price_hnl)
      order = DepositOrder.create!(
        service_slug: @service.slug, amount_hnl: @service.price_hnl, price_atomic: pricing.price_atomic,
        rate_hnl_per_usd: pricing.effective_rate, fee_bps: pricing.fee_bps,
        beneficiary_name: name, account_number: account, concept: concept, contact_email: email
      )
      Result.success(status: 202, content_type: "application/json", body: body_for(order).to_json, order: order)
    end

    private

    def body_for(order)
      order.public_status.merge(status: "pending", eta: "within 24 hours", status_url: "#{Rails.configuration.x402.public_host}/orders/#{order.token}")
    end

    def bad_request(message)
      Result.success(status: 422, content_type: "application/json", body: { error: message }.to_json)
    end

    def limit_reached
      Result.success(status: 429, content_type: "application/json",
                     body: { error: "This account already received #{MAX_ORDERS_PER_ACCOUNT_PER_DAY} deposits in the last 24 hours; try again tomorrow." }.to_json)
    end
  end
end
