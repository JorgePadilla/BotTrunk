# frozen_string_literal: true

module Notifications
  # A seller has been approved or rejected. They asked days ago; the one thing
  # they are owed is being told, either way.
  class AnnounceReview
    def initialize(inquiry:)
      @inquiry = inquiry
    end

    def call
      return Result.success(sent: false, reason: :still_pending) if @inquiry.blank? || @inquiry.pending?

      Deliver.call(SellerMailer.with(inquiry: @inquiry).public_send(@inquiry.status == "approved" ? :approved : :rejected))
      Result.success(sent: true)
    end
  end
end
