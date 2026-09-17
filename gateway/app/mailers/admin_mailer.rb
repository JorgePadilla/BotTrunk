# frozen_string_literal: true

# Operational mail to whoever runs the queue (ADMIN_EMAIL). Without that
# address there is no alert and no digest: these never guess a recipient.
#
# Bank account numbers are deliberately masked here. They are encrypted at
# rest, email is not a private channel, and the admin queue — which needs a
# password — has the full number a transfer actually requires.
class AdminMailer < ApplicationMailer
  # The subject formats money and addresses the same way every view does.
  include MoneyHelper

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

  # A buyer asking for work. The subject says which kind, because a request
  # for something we do not list is the one that changes what we build next.
  def new_request
    @request = params[:request]
    return if admin.blank?

    mail(to: admin, subject: request_subject)
  end

  # Every settled call. The subject carries the whole story, because that is
  # all a phone notification shows: who paid, for what, how much — and whether
  # this wallet has ever paid us before, which is the only line that means a
  # customer rather than a test.
  def call_settled
    @call = params[:call]
    @first_from_payer = params[:first_from_payer]
    return if admin.blank? || @call.blank?

    mail(to: admin, subject: call_subject)
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

  def request_subject
    who = @request.service ? @request.service.name : "something we don't sell"
    "Service request — #{who}"
  end

  def call_subject
    who = @call.payer_address.present? ? " from #{short_address(@call.payer_address)}" : ""
    "#{@first_from_payer ? 'New payer' : 'Paid call'} — #{@call.service_slug}, #{usdc(@call.amount)}#{who}"
  end

  def hnl(amount) = "L#{ActiveSupport::NumberHelper.number_to_delimited(amount.to_i)}"
end
