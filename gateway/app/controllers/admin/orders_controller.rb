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
      redirect_to admin_orders_path, notice: "Order #{order.token} marked delivered."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_orders_path, alert: e.message
    end

    def refund
      order = DepositOrder.find_by!(token: params[:token])
      order.refund!(transaction_id: params[:refund_transaction_id], notes: params[:notes])
      redirect_to admin_orders_path, notice: "Order #{order.token} marked refunded."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_orders_path, alert: e.message
    end
  end
end
