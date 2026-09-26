# frozen_string_literal: true

module Fulfillers
  # Built-in, human-fulfilled service: an agent describes what it wants to buy,
  # a person contacts suppliers by phone and email and comes back with real
  # quotes. An agent can find two hundred suppliers in a minute and cannot get
  # one of them to quote; that gap is the whole product.
  #
  # Like DepositBac this only validates and opens the order — the money is the
  # normal x402 loop and the work is the admin queue (/admin/work_orders).
  # It runs before settlement, so the order starts `awaiting_payment` and
  # Gateway::HandlePaidCall flips it to `pending` once the USDC lands.
  class RfqGlobal
    MAX_OPEN_JOBS = 12          # what one person can carry at the promised pace
    BRIEF = (40..4_000)
    MAX_SUPPLIERS = 10

    def initialize(input:, service:)
      @input = input.is_a?(Hash) ? input : {}
      @service = service
    end

    def call
      brief = @input["brief"].to_s.strip
      quantity = @input["quantity"].to_s.squish.presence
      destination = @input["destination"].to_s.squish.presence
      email = @input["contact_email"].to_s.strip.presence

      return bad_request("brief is required: what you want quoted, in #{BRIEF.min}–#{BRIEF.max} characters") unless brief.length.between?(BRIEF.min, BRIEF.max)
      return bad_request("quantity is required, e.g. \"500 units\" or \"2 pallets\"") if quantity.blank?
      return bad_request("destination is required: where the goods must be delivered or quoted to") if destination.blank?
      return bad_request("contact_email is not a valid email") if email && !email.match?(URI::MailTo::EMAIL_REGEXP)
      return at_capacity if WorkOrder.queue.count >= MAX_OPEN_JOBS

      order = WorkOrder.create!(
        service_slug: @service.slug, price_atomic: @service.price_atomic, contact_email: email,
        brief: brief, params: { quantity: quantity, destination: destination, suppliers: MAX_SUPPLIERS }
      )
      Result.success(status: 202, content_type: "application/json", body: body_for(order).to_json, order: order)
    end

    private

    def body_for(order)
      # The order is still `awaiting_payment` here — settlement is the next
      # step in HandlePaidCall — so say what it is about to be, the way the
      # deposit fulfiller does.
      order.public_status.merge(
        status: "pending", eta: order.eta,
        status_url: "#{Rails.configuration.x402.public_host}/orders/#{order.token}",
        next: "Poll status_url. When status is delivered, `result` holds one entry per supplier reached."
      )
    end

    def bad_request(message)
      Result.success(status: 422, content_type: "application/json", body: { error: message }.to_json)
    end

    # Refusing a job we cannot staff costs the buyer nothing: a 4xx is never
    # settled. Better an honest 429 than a promise we miss by a week.
    def at_capacity
      Result.success(status: 429, content_type: "application/json",
                     body: { error: "The queue is full (#{MAX_OPEN_JOBS} jobs in progress). Nothing was charged — try again in a day or two." }.to_json)
    end
  end
end
