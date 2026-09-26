# frozen_string_literal: true

require "test_helper"

module Notifications
  class DailyDigestTest < ActiveSupport::TestCase
    test "counts what is waiting and what moved in the last 24 hours" do
      waiting = build_order(amount_hnl: 2_500)
      waiting.update!(created_at: 30.hours.ago)
      done = build_order(amount_hnl: 1_000)
      done.deliver!(receipt_reference: "BAC-7")
      old = build_order(amount_hnl: 5_000)
      old.deliver!(receipt_reference: "BAC-OLD")
      old.update!(delivered_at: 3.days.ago)

      report = DailyDigest.new.call[:report]

      assert_equal [ waiting.id ], report.queue.map(&:id)
      assert_equal 2_500, report.owed_hnl
      assert_equal [ done.id ], report.delivered.map(&:id)
      assert_match(/day/, report.oldest)
    end

    test "jobs waiting at a desk are counted beside the deposits" do
      job = build_job
      job.update!(created_at: 30.hours.ago)
      build_job(status: "delivered", delivered_at: Time.current, result: { "quotes" => [] })

      report = DailyDigest.new.call[:report]

      assert_equal [ job.id ], report.jobs.map(&:id), "only what is still waiting"
      assert_match(/day/, report.oldest_job)
    end

    test "an empty day still produces a report and an email" do
      with_admin_email do
        report = DailyDigest.new.call[:report]

        assert_empty report.queue
        assert_equal 0, report.calls
        assert_nil report.oldest
      end

      assert_equal 1, ActionMailer::Base.deliveries.size
    end

    # The cron container exits seconds after this returns. A queued job would
    # die with it — which is exactly what happened on Sep 12: enqueued at
    # 09:01:24, process gone at 09:01:26, no email, exit status 0.
    test "the digest is sent, not enqueued, because nothing survives to run it" do
      with_admin_email do
        assert_no_enqueued_emails { DailyDigest.new.call }
      end

      assert_equal [ MailHelpers::ADMIN ], ActionMailer::Base.deliveries.flat_map(&:to)
    end

    test "with no ADMIN_EMAIL the digest still reports and sends nothing" do
      with_admin_email(nil) do
        assert_equal 0, DailyDigest.new.call[:report].calls
      end

      assert_empty ActionMailer::Base.deliveries
    end
  end
end
