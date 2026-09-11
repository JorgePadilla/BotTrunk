# frozen_string_literal: true

# Operational mail to whoever runs the queue (ADMIN_EMAIL). Without that
# address there is no alert and no digest: these never guess a recipient.
#
# Bank account numbers are deliberately masked here. They are encrypted at
# rest, email is not a private channel, and the admin queue — which needs a
# password — has the full number a transfer actually requires.
class AdminMailer < ApplicationMailer
  def new_order
    @order = params[:order]
    return if admin.blank?

    mail(to: admin, subject: "New deposit to make — #{hnl(@order.amount_hnl)} to #{@order.beneficiary_name}")
  end

  def new_inquiry
    @inquiry = params[:inquiry]
    return if admin.blank?

    mail(to: admin, subject: "Seller inquiry — #{@inquiry.service_name}")
  end

  def digest
    @report = params[:report]
    return if admin.blank?

    mail(to: admin, subject: digest_subject)
  end

  private

  def admin = self.class.admin_address

  def digest_subject
    open = @report[:queue].size
    return "BotTrunk daily — nothing waiting" if open.zero?

    "BotTrunk daily — #{open} deposit#{'s' if open != 1} waiting#{', oldest ' + @report[:oldest] if @report[:oldest]}"
  end

  def hnl(amount) = "L#{ActiveSupport::NumberHelper.number_to_delimited(amount.to_i)}"
end
