# frozen_string_literal: true

module Admin
  # The fulfilment queue: pending deposits to make, and what is done.
  class OrdersController < BaseController
    def index
      @queue = DepositOrder.queue.includes(:call)
      @done = DepositOrder.done.includes(:call).limit(50)
      @abandoned = DepositOrder.abandoned.limit(10)
    end

    def deliver
      order = DepositOrder.find_by!(token: params[:token])
      order.deliver!(receipt_reference: params[:receipt_reference], notes: params[:notes])
      Notifications::AnnounceOrderUpdate.new(order: order).call
      redirect_to admin_orders_path, notice: "Order #{order.token} marked delivered.#{notified(order)}"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_orders_path, alert: e.message
    end

    def refund
      order = DepositOrder.find_by!(token: params[:token])
      order.refund!(transaction_id: params[:refund_transaction_id], notes: params[:notes])
      Notifications::AnnounceOrderUpdate.new(order: order).call
      redirect_to admin_orders_path, notice: "Order #{order.token} marked refunded.#{notified(order)}"
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_orders_path, alert: e.message
    end

    private

    # Say so in the flash, so nobody has to guess whether the buyer was told.
    def notified(order) = order.contact_email.present? ? " Emailed #{order.contact_email}." : ""
  end
end
