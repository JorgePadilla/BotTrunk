# frozen_string_literal: true

# Emails to sellers: their early-access request, its review, and signing in.
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

  # The link opens a page with a button (Sellers::SessionsController#confirm),
  # so a mail scanner that follows it does not spend it.
  def sign_in_link
    @seller = params[:seller]
    @url = seller_confirm_sign_in_url(token: params[:token])

    mail(to: @seller.email, subject: "Your BotTrunk sign-in link")
  end

  # Sent once to sellers approved before accounts existed.
  def invitation
    @inquiry = params[:inquiry]
    @url = seller_sign_in_url(email: @inquiry.email)

    mail(to: @inquiry.email, subject: "Seller accounts are open on BotTrunk")
  end

  def listing_approved
    @listing = params[:listing]

    mail(to: @listing.seller.email, subject: "#{@listing.name} is live on BotTrunk")
  end

  def listing_rejected
    @listing = params[:listing]

    mail(to: @listing.seller.email, subject: "About #{@listing.name} on BotTrunk")
  end

  def payout_sent
    @payout = params[:payout]

    mail(to: @payout.seller.email, subject: "We sent you #{ActionController::Base.helpers.number_to_currency(BigDecimal(@payout.amount) / 1_000_000)} USDC")
  end
end
