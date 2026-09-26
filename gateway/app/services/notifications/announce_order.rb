# frozen_string_literal: true

module Notifications
  # An order has settled and joined a queue. Two people care: whoever has to do
  # the work inside the promised window, and — when they left an address — the
  # human behind the agent that paid.
  #
  # Deposits and desk work have different queues and different mail, so the
  # order tells us which it is rather than the caller having to.
  class AnnounceOrder
    def initialize(order:)
      @order = order
    end

    def call
      return Result.success(sent: false) if @order.blank?

      Deliver.call(admin_mail) if ApplicationMailer.admin_address
      Deliver.call(DepositMailer.with(order: @order).received) if deposit? && @order.contact_email.present?
      Result.success(sent: true)
    end

    private

    def deposit? = @order.is_a?(DepositOrder)

    def admin_mail
      deposit? ? AdminMailer.with(order: @order).new_order : AdminMailer.with(order: @order).new_work_order
    end
  end
end
