# frozen_string_literal: true

module Notifications
  # A seller asked to list something: tell us, and tell them we heard.
  class AnnounceInquiry
    def initialize(inquiry:)
      @inquiry = inquiry
    end

    def call
      return Result.success(sent: false) if @inquiry.blank?

      Deliver.call(AdminMailer.with(inquiry: @inquiry).new_inquiry) if ApplicationMailer.admin_address
      Deliver.call(SellerMailer.with(inquiry: @inquiry).acknowledgement)
      Result.success(sent: true)
    end
  end
end
