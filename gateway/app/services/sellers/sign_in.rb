# frozen_string_literal: true

module Sellers
  # Exchanges a sign-in link for the seller it belongs to, and spends it.
  class SignIn
    def initialize(token:, now: Time.current)
      @token = token.to_s
      @now = now
    end

    def call
      seller = Seller.find_by_token_for(:sign_in, @token)
      return Result.failure("That sign-in link has expired or was already used. Ask for a new one.", code: :invalid_token) unless seller
      return Result.failure("This account is suspended. Write to hello@bottrunk.com.", code: :suspended) unless seller.active?

      seller.update!(last_signed_in_at: @now)
      Result.success(seller: seller)
    end
  end
end
