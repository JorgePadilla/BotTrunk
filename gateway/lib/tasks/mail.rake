# frozen_string_literal: true

namespace :mail do
  desc "Send the daily operations digest to ADMIN_EMAIL"
  task digest: :environment do
    result = Notifications::DailyDigest.new.call
    report = result[:report]
    puts "[mail:digest] #{report.queue.size} waiting, #{report.calls} calls, #{report.volume} µUSDC in the last 24 h"
  end

  desc "Send one of each email to ADMIN_EMAIL using the newest real records (nothing is changed)"
  task preview: :environment do
    to = ENV["ADMIN_EMAIL"].presence or abort "Set ADMIN_EMAIL first."
    order = DepositOrder.order(created_at: :desc).first or abort "No deposit orders to render."
    inquiry = SellerInquiry.order(created_at: :desc).first

    AdminMailer.with(order: order).new_order.deliver_now
    DepositMailer.with(order: order.tap { |o| o.contact_email = to }).received.deliver_now
    AdminMailer.with(inquiry: inquiry).new_inquiry.deliver_now if inquiry
    Notifications::DailyDigest.new.call
    puts "[mail:preview] sent to #{to}"
  end
end
