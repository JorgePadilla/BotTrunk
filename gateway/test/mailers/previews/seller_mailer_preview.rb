# frozen_string_literal: true

# Previews are required on their own, outside the autoloader, so the shared
# sample records come in explicitly.
require_relative "mail_preview_data"

class SellerMailerPreview < ActionMailer::Preview
  def acknowledgement = SellerMailer.with(inquiry: MailPreviewData.inquiry).acknowledgement
end
