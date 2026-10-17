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

    test "paid calls from outside wallets are counted apart from ours" do
      payers = [ Rails.configuration.x402.own_payers.first, "OUTSIDE-1", "OUTSIDE-1", "OUTSIDE-2" ]
      payers.each_with_index do |payer, i|
        Call.create!(service_slug: "page-kind", pay_to: "GATEWAY", network: "algorand:x", asset: "31566704", amount: 20_000,
                     commission: 3_000, seller_amount: 17_000, payer_address: payer, transaction_id: "D#{i}", status: "settled")
      end

      with_admin_email do
        report = DailyDigest.new.call[:report]
        assert_equal 4, report.calls
        assert_equal 3, report.outside_calls
        assert_equal 2, report.outside_payers
      end
      assert_match "3 from 2 payers", ActionMailer::Base.deliveries.last.text_part.body.to_s
    end

    test "the digest says what is owed to sellers and not yet paid" do
      listing = live_listing
      Call.create!(service_slug: listing.slug, seller: listing.seller, pay_to: "G", network: "algorand:x", asset: "31566704",
                   amount: 2_000_000, commission: 300_000, seller_amount: 1_700_000, transaction_id: "S1", status: "settled")
      listing.seller.payouts.create!(amount: 700_000, transaction_id: "D" * 52, paid_at: Time.current)

      with_admin_email do
        assert_equal 1_000_000, DailyDigest.new.call[:report].owed_to_sellers
      end
      assert_match "$1.00 USDC to sellers", ActionMailer::Base.deliveries.last.text_part.body.to_s
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
