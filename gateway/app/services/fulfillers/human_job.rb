# frozen_string_literal: true

module Fulfillers
  # Every service where the work is done by a person at a desk or an address.
  # It reads what to ask for from the catalog entry's `job:` spec, so adding
  # one of these is a catalog entry and no new class:
  #
  #   job: { eta: "within 5 business days", capacity: 12,
  #          required: { "brief" => { min: 40, max: 4_000 }, "quantity" => {} } }
  #
  # Like DepositBac it only validates and opens the order — the money is the
  # normal x402 loop and the work is the queue at /admin/work_orders. It runs
  # before settlement, so the order starts `awaiting_payment` and
  # Gateway::HandlePaidCall flips it to `pending` once the USDC lands.
  class HumanJob
    DEFAULT_MAX = 2_000
    BRIEF_FIELD = "brief"

    def initialize(input:, service:)
      @input = input.is_a?(Hash) ? input : {}
      @service = service
    end

    def call
      values, problem = collect
      return problem if problem

      email = @input["contact_email"].to_s.strip.presence
      return bad_request("contact_email is not a valid email") if email && !email.match?(URI::MailTo::EMAIL_REGEXP)
      return at_capacity if over_capacity?

      order = WorkOrder.create!(
        service_slug: @service.slug, price_atomic: @service.price_atomic, contact_email: email,
        brief: values[BRIEF_FIELD] || summary_of(values), params: values.except(BRIEF_FIELD).merge(extra_params)
      )
      Result.success(status: 202, content_type: "application/json", body: body_for(order).to_json, order: order)
    end

    private

    # Anything a subclass computed and wants frozen into the order — a quote
    # taken at the moment of sale, say. Empty for a plain job.
    def extra_params = {}

    # Returns [values, failure]. The first missing or malformed field wins, so
    # the buyer gets one clear thing to fix rather than a list.
    def collect
      values = {}
      @service.job_fields.each do |name, rules|
        value = @input[name].to_s.squish
        min = rules[:min] || 1
        max = rules[:max] || DEFAULT_MAX
        return [ nil, bad_request(message_for(name, rules, min, max)) ] unless value.length.between?(min, max)

        values[name] = value
      end
      [ values, nil ]
    end

    def message_for(name, rules, min, max)
      return "#{name} is required: #{rules[:hint]}" if rules[:hint] && min <= 1
      return "#{name} is required (#{min}–#{max} characters)#{rules[:hint] ? ": #{rules[:hint]}" : ""}" if min > 1

      "#{name} is required"
    end

    # A service with no `brief` field still needs one line the operator can
    # read at a glance in the queue.
    def summary_of(values) = values.map { |name, value| "#{name.humanize}: #{value}" }.join("\n")

    def over_capacity?
      capacity = @service.job_capacity
      capacity.present? && WorkOrder.queue.where(service_slug: @service.slug).count >= capacity
    end

    def body_for(order)
      # Still `awaiting_payment` here — settlement is the next step in
      # HandlePaidCall — so say what it is about to be.
      order.public_status.merge(
        status: "pending", eta: order.eta,
        status_url: "#{Rails.configuration.x402.public_host}/orders/#{order.token}",
        next: "Poll status_url. When status is delivered, `result` holds the work."
      )
    end

    def bad_request(message)
      Result.success(status: 422, content_type: "application/json", body: { error: message }.to_json)
    end

    # Refusing work we cannot staff costs the buyer nothing: a 4xx is never
    # settled. Better an honest 429 than a promise missed by a week.
    def at_capacity
      Result.success(status: 429, content_type: "application/json",
                     body: { error: "This service has #{@service.job_capacity} jobs in progress, which is all it can carry. Nothing was charged — try again in a day or two." }.to_json)
    end
  end
end
