# frozen_string_literal: true

# Previews are required on their own, outside the autoloader, so the shared
# sample records come in explicitly.
require_relative "mail_preview_data"

# Look at every email without sending one: http://localhost:3000/rails/mailers
# Records are built in memory; nothing is written.
class DepositMailerPreview < ActionMailer::Preview
  def received = DepositMailer.with(order: MailPreviewData.order).received

  def delivered
    DepositMailer.with(order: MailPreviewData.order(
      status: "delivered", receipt_reference: "BAC-2026-884213", delivered_at: 2.hours.ago, notes: "Sent from the BAC app at 9:41."
    )).delivered
  end

  def refunded
    DepositMailer.with(order: MailPreviewData.order(
      status: "refunded", refunded_at: 1.hour.ago, notes: "The account number was rejected by the bank.",
      refund_transaction_id: "KFCOJ5GXBDZKTHAKBKYFULKICYDMYAYW3EZ3VQ5NHYQESQJ6C5UQ"
    )).refunded
  end
end
