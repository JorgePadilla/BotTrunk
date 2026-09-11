# frozen_string_literal: true

# Previews are required on their own, outside the autoloader, so the shared
# sample records come in explicitly.
require_relative "mail_preview_data"

class AdminMailerPreview < ActionMailer::Preview
  def new_order = AdminMailer.with(order: MailPreviewData.order).new_order

  def new_inquiry = AdminMailer.with(inquiry: MailPreviewData.inquiry).new_inquiry

  def digest = AdminMailer.with(report: MailPreviewData.digest).digest

  def digest_empty = AdminMailer.with(report: MailPreviewData.digest(empty: true)).digest
end
