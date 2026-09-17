# frozen_string_literal: true

module Notifications
  # A buyer asked for work: tell us, and tell them we heard.
  class AnnounceRequest
    def initialize(request:)
      @request = request
    end

    def call
      return Result.success(sent: false) if @request.blank?

      Deliver.call(AdminMailer.with(request: @request).new_request) if ApplicationMailer.admin_address
      Deliver.call(BuyerMailer.with(request: @request).acknowledgement)
      Result.success(sent: true)
    end
  end
end
