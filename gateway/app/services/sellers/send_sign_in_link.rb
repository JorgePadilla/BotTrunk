# frozen_string_literal: true

module Sellers
  # Emails a one-time sign-in link. An address we have never seen becomes a
  # seller here, before the link is clicked, because the link has to belong to
  # a record; nothing is listed or payable until that seller also lists an API
  # and a person approves it.
  #
  # The answer is the same whether or not the address was known, so the form
  # cannot be used to find out who sells on BotTrunk.
  class SendSignInLink
    def initialize(email:)
      @email = email.to_s
    end

    def call
      seller = Seller.find_or_create_by!(email: @email.strip.downcase)
      return Result.failure("This account is suspended. Write to hello@bottrunk.com.", code: :suspended) unless seller.active?

      Notifications::Deliver.call(SellerMailer.with(seller: seller, token: seller.generate_token_for(:sign_in)).sign_in_link)
      Result.success(seller: seller)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.to_sentence, code: :invalid)
    end
  end
end
