# frozen_string_literal: true

module Notifications
  # A deposit has settled and joined the queue. Two people care: whoever has
  # to make the bank transfer within 24 hours, and — when they left an
  # address — the human behind the agent that paid.
  class AnnounceOrder
    def initialize(order:)
      @order = order
    end

    def call
      return Result.success(sent: false) if @order.blank?

      Deliver.call(AdminMailer.with(order: @order).new_order)
      Deliver.call(DepositMailer.with(order: @order).received)
      Result.success(sent: true)
    end
  end
end
