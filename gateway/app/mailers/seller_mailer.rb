# frozen_string_literal: true

# The one email a seller gets for now: proof their form submission landed
# somewhere a person will read. Sign-up, keys and payouts come with Phase 1.
class SellerMailer < ApplicationMailer
  def acknowledgement
    @inquiry = params[:inquiry]

    mail(to: @inquiry.email, subject: "We got your BotTrunk listing request")
  end

  def approved
    @inquiry = params[:inquiry]

    mail(to: @inquiry.email, subject: "#{@inquiry.service_name} is approved for BotTrunk")
  end

  # Sent because the alternative is silence, which is what every other
  # marketplace does and what everyone complains about.
  def rejected
    @inquiry = params[:inquiry]

    mail(to: @inquiry.email, subject: "About #{@inquiry.service_name} on BotTrunk")
  end
end
