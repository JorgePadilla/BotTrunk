# frozen_string_literal: true

# Every email BotTrunk sends. Plain, table-based HTML with a text part beside
# it — these are receipts, not marketing, and they have to survive a bank
# app's webview as readily as Gmail.
class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM", "BotTrunk <no-reply@bottrunk.com>") },
          reply_to: -> { ENV.fetch("MAIL_REPLY_TO", "hello@bottrunk.com") }

  layout "mailer"

  helper MoneyHelper
  helper MailHelper

  # Where operational alerts go. Blank in development and on a fresh deploy,
  # which is why every admin mailer checks it before building a message.
  def self.admin_address = ENV["ADMIN_EMAIL"].presence
end
