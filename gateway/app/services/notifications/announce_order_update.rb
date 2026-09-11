# frozen_string_literal: true

module Notifications
  # The queue moved: a deposit was delivered or refunded. Only the buyer is
  # told — the person who changed the status is the one who did the work.
  class AnnounceOrderUpdate
    MAILS = { "delivered" => :delivered, "refunded" => :refunded }.freeze

    def initialize(order:)
      @order = order
    end

    def call
      action = MAILS[@order&.status]
      return Result.success(sent: false, reason: :nothing_to_say) if action.nil?
      return Result.success(sent: false, reason: :no_recipient) if @order.contact_email.blank?

      Deliver.call(DepositMailer.with(order: @order).public_send(action))
      Result.success(sent: true)
    end
  end
end
