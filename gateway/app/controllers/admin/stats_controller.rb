# frozen_string_literal: true

module Admin
  # GET /admin/stats — what is happening: visits, probes, payments, money.
  class StatsController < BaseController
    def show
      @days = params[:days].to_i.clamp(7, 90)
      @days = 30 if params[:days].blank?
      @report = Stats::Overview.new(days: @days).call[:report]
      @queue_count = DepositOrder.queue.count
    end
  end
end
