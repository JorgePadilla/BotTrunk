# frozen_string_literal: true

module Sellers
  # Records an early-access request from a seller. Converts the USDC price the
  # form collected into atomic units; nothing else here knows about decimals.
  class CreateInquiry
    def initialize(email:, service_name:, upstream_url:, price_usdc:, notes: nil)
      @email = email.to_s.strip.downcase
      @service_name = service_name.to_s.strip
      @upstream_url = upstream_url.to_s.strip
      @price_usdc = price_usdc.to_s.strip
      @notes = notes.to_s.strip.presence
    end

    def call
      inquiry = SellerInquiry.new(email: @email, service_name: @service_name, upstream_url: @upstream_url,
                                  price_atomic: to_atomic(@price_usdc), notes: @notes, price_usdc: @price_usdc)
      if inquiry.save
        Result.success(inquiry: inquiry)
      else
        Result.failure(inquiry.errors.full_messages.to_sentence, code: :invalid, data: { inquiry: inquiry })
      end
    end

    private

    def to_atomic(usdc)
      return nil if usdc.blank?

      (BigDecimal(usdc) * 1_000_000).to_i
    rescue ArgumentError
      nil
    end
  end
end
