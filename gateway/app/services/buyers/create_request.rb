# frozen_string_literal: true

module Buyers
  # Records a buyer asking for work: either one of the `on_request` services,
  # or something the catalog does not have. Converts the optional USDC budget
  # into atomic units; nothing else here knows about decimals.
  class CreateRequest
    def initialize(email:, details:, service_slug: nil, budget_usdc: nil)
      @email = email.to_s.strip.downcase
      @details = details.to_s.strip
      @service_slug = service_slug.to_s.strip.presence
      @budget_usdc = budget_usdc.to_s.strip
    end

    def call
      request = ServiceRequest.new(email: @email, details: @details, service_slug: @service_slug,
                                   budget_atomic: to_atomic(@budget_usdc), budget_usdc: @budget_usdc)
      if request.save
        Notifications::AnnounceRequest.new(request: request).call
        Result.success(request: request)
      else
        Result.failure(request.errors.full_messages.to_sentence, code: :invalid, data: { request: request })
      end
    end

    private

    # A budget is optional, so a blank box is not an error — but something we
    # cannot read as a number is dropped rather than guessed at, and the row
    # still saves. The request is the point; the budget is a hint.
    def to_atomic(usdc)
      return nil if usdc.blank?

      (BigDecimal(usdc) * 1_000_000).to_i
    rescue ArgumentError
      nil
    end
  end
end
