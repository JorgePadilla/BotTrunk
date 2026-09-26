# frozen_string_literal: true

module Admin
  # The desk queue: jobs a person is doing — calls to make, quotes to chase —
  # and what is finished. Deposits have their own queue at /admin/orders
  # because the work and the proof are nothing alike.
  class WorkOrdersController < BaseController
    def index
      @queue = WorkOrder.queue.includes(:call)
      @done = WorkOrder.done.includes(:call).limit(50)
      @abandoned = WorkOrder.abandoned.limit(10)
    end

    def deliver
      order = WorkOrder.find_by!(token: params[:token])
      order.deliver!(result: parsed_result, notes: params[:notes])
      redirect_to admin_work_orders_path, notice: "Job #{order.token} marked delivered."
    rescue ActiveRecord::RecordInvalid, JSON::ParserError => e
      redirect_to admin_work_orders_path, alert: e.message
    end

    def refund
      order = WorkOrder.find_by!(token: params[:token])
      order.refund!(transaction_id: params[:refund_transaction_id], notes: params[:notes])
      redirect_to admin_work_orders_path, notice: "Job #{order.token} marked refunded."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_work_orders_path, alert: e.message
    end

    private

    # The operator pastes JSON (one entry per supplier). Anything that is not
    # JSON is kept verbatim under `notes`, so a hurried paste is never lost.
    def parsed_result
      raw = params[:result].to_s.strip
      return {} if raw.blank?

      JSON.parse(raw)
    rescue JSON::ParserError
      { "notes" => raw }
    end
  end
end
