# frozen_string_literal: true

namespace :mail do
  desc "Send the daily operations digest to ADMIN_EMAIL"
  task digest: :environment do
    result = Notifications::DailyDigest.new.call
    report = result[:report]
    puts "[mail:digest] #{report.queue.size} waiting, #{report.calls} calls, #{report.volume} µUSDC in the last 24 h"
  end

  desc "Send one of each email to ADMIN_EMAIL (real records when there are any, samples otherwise). Writes nothing."
  task preview: :environment do
    to = ENV["ADMIN_EMAIL"].presence
    abort "Set ADMIN_EMAIL first — in gateway/.env.local, or ADMIN_EMAIL=you@example.com bin/rails mail:preview" if to.nil?

    method = ActionMailer::Base.delivery_method
    if method == :test
      missing = %w[SMTP_ADDRESS SMTP_USER_NAME SMTP_PASSWORD].reject { |k| ENV[k].present? }
      abort "SMTP is not configured (delivery_method is :test), so nothing would leave this machine.\n" \
            "#{missing.any? ? "Missing: #{missing.join(', ')}. Put them" : 'Put SMTP_ADDRESS=smtp.resend.com, SMTP_USER_NAME=resend and SMTP_PASSWORD=<resend api key>'} in gateway/.env.local.\n" \
            "That file is read in config/boot.rb, so a value added after the server started needs a restart.\n" \
            "To look at every email without sending one: http://localhost:3000/rails/mailers"
    end

    order = DepositOrder.order(created_at: :desc).first || MailPreviewTask.sample_order
    order.contact_email = to
    inquiry = SellerInquiry.order(created_at: :desc).first || MailPreviewTask.sample_inquiry
    inquiry.email = to

    MailPreviewTask.with_admin(to) do
      DepositMailer.with(order: order).received.deliver_now
      DepositMailer.with(order: MailPreviewTask.delivered(order)).delivered.deliver_now
      DepositMailer.with(order: MailPreviewTask.refunded(order)).refunded.deliver_now
      AdminMailer.with(order: order).new_order.deliver_now
      AdminMailer.with(inquiry: inquiry).new_inquiry.deliver_now
      SellerMailer.with(inquiry: inquiry).acknowledgement.deliver_now
      AdminMailer.with(report: Notifications::DailyDigest.new.report.to_h).digest.deliver_now
    end

    puts "[mail:preview] seven emails sent to #{to} over #{method} from #{ActionMailer::Base.default[:from]}"
    puts "[mail:preview] nothing was written: #{order.persisted? ? 'the order shown is real but unchanged' : 'no orders exist yet, so a sample was used'}"
  end

end

# Sample records and state shuffling for mail:preview. A module so the helpers
# do not end up as methods on Object, which is what a bare `def` in a rake
# file does.
module MailPreviewTask
  module_function

  # The preview renders delivered/refunded states without saving them, so a
  # real order in the queue is never advanced by looking at its email.
  def delivered(order)
    order.dup.tap { |o| o.assign_attributes(status: "delivered", receipt_reference: "BAC-2026-884213", delivered_at: Time.current, notes: "Sample — nothing was saved.") }
  end

  def refunded(order)
    order.dup.tap do |o|
      o.assign_attributes(status: "refunded", refunded_at: Time.current, notes: "Sample — nothing was saved.",
                          refund_transaction_id: "KFCOJ5GXBDZKTHAKBKYFULKICYDMYAYW3EZ3VQ5NHYQESQJ6C5UQ")
    end
  end

  def sample_order
    DepositOrder.new(token: "sample", service_slug: "deposit-bac-2500", beneficiary_name: "Juana Martínez Andino",
                     bank: "BAC Credomatic", account_number: "731234567890", amount_hnl: 2_500,
                     price_atomic: 106_275_305, fee_bps: 500, rate_hnl_per_usd: BigDecimal("26.2000"),
                     status: "pending", concept: "Factura 1042", created_at: 3.hours.ago)
  end

  def sample_inquiry
    SellerInquiry.new(service_name: "Honduran court records lookup", upstream_url: "https://api.example.com/v1/records",
                      price_atomic: 250_000, notes: "Sample inquiry — nothing was saved.", created_at: Time.current)
  end

  def with_admin(address)
    previous = ENV["ADMIN_EMAIL"]
    ENV["ADMIN_EMAIL"] = address
    yield
  ensure
    ENV["ADMIN_EMAIL"] = previous
  end
end
