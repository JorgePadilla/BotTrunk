# frozen_string_literal: true

# Previews are required on their own, outside the autoloader, so the shared
# sample records come in explicitly.
require_relative "mail_preview_data"

class SellerMailerPreview < ActionMailer::Preview
  def acknowledgement = SellerMailer.with(inquiry: MailPreviewData.inquiry).acknowledgement

  def sign_in_link = SellerMailer.with(seller: Seller.new(email: "seller@example.com"), token: "preview-token").sign_in_link

  def invitation = SellerMailer.with(inquiry: MailPreviewData.inquiry).invitation
end
