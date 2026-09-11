# frozen_string_literal: true

module Notifications
  # One email a day with the state of the business: what is still waiting,
  # what moved, what was earned. The per-order alert says "go do this now";
  # the digest is the thing you read with coffee and notice that an order from
  # yesterday is still sitting there.
  #
  # Sent by `bin/rails mail:digest` (a scheduled job), so it takes `now` and
  # never reads the clock twice.
  class DailyDigest
    WINDOW = 24.hours

    Report = Data.define(:generated_at, :queue, :oldest, :delivered, :refunded, :calls, :volume, :commission, :inquiries, :owed_hnl)

    def initialize(now: Time.current)
      @now = now
    end

    def call
      current = report
      Deliver.call(AdminMailer.with(report: current.to_h).digest)
      Result.success(report: current)
    end

    # The same numbers without sending anything — for `bin/rails mail:preview`
    # and for anywhere else that wants to look at the day without mailing it.
    def report
      queue = DepositOrder.queue.to_a
      calls = Call.since(since)
      Report.new(
        generated_at: @now,
        queue: queue,
        oldest: queue.first && age(queue.first.created_at),
        owed_hnl: queue.sum(&:amount_hnl),
        delivered: DepositOrder.where(status: "delivered", delivered_at: since..).order(:delivered_at).to_a,
        refunded: DepositOrder.where(status: "refunded", refunded_at: since..).order(:refunded_at).to_a,
        calls: calls.count,
        volume: calls.sum(:amount),
        commission: calls.sum(:commission),
        inquiries: SellerInquiry.where(created_at: since..).order(:created_at).to_a
      )
    end

    private

    def since = @now - WINDOW

    # "19 hours", "2 days" — enough to feel late, without a timestamp to decode.
    def age(time)
      ActionController::Base.helpers.time_ago_in_words(time)
    end
  end
end
