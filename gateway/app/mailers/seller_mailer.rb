# frozen_string_literal: true

# The one email a seller gets for now: proof their form submission landed
# somewhere a person will read. Sign-up, keys and payouts come with Phase 1.
class SellerMailer < ApplicationMailer
  def acknowledgement
    @inquiry = params[:inquiry]

    mail(to: @inquiry.email, subject: "We got your BotTrunk listing request")
  end
end
