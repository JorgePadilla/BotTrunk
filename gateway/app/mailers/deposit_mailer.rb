# frozen_string_literal: true

# What the buyer hears about a lempira deposit. `contact_email` is optional —
# an agent with a wallet has no inbox — so every one of these is skipped
# silently when the order has no address. The order token and
# GET /orders/:token remain the authoritative receipt either way.
class DepositMailer < ApplicationMailer
  def received
    @order = params[:order]
    return unless to?

    mail(to: @order.contact_email,
         subject: "Deposit received — #{number_to_hnl(@order.amount_hnl)} to #{@order.beneficiary_name}")
  end

  def delivered
    @order = params[:order]
    return unless to?

    mail(to: @order.contact_email,
         subject: "Deposit sent — #{number_to_hnl(@order.amount_hnl)} to #{@order.beneficiary_name}")
  end

  def refunded
    @order = params[:order]
    return unless to?

    mail(to: @order.contact_email,
         subject: "Deposit refunded — #{number_to_hnl(@order.amount_hnl)} returned in USDC")
  end

  private

  def to? = @order&.contact_email.present?

  def number_to_hnl(amount) = "L#{ActiveSupport::NumberHelper.number_to_delimited(amount.to_i)}"
end
