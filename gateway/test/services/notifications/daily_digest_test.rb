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

    test "an empty day still produces a report and an email" do
      with_admin_email do
        assert_enqueued_emails 1 do
          report = DailyDigest.new.call[:report]

          assert_empty report.queue
          assert_equal 0, report.calls
          assert_nil report.oldest
        end
      end
    end
  end
end
