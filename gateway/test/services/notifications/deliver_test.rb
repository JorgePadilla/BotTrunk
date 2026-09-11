# frozen_string_literal: true

require "test_helper"

module Notifications
  class DeliverTest < ActiveSupport::TestCase
    test "enqueues a message" do
      assert_enqueued_emails 1 do
        assert Deliver.call(DepositMailer.with(order: build_order).received).success?
      end
    end

    # Reading `mail.to` here processes the mailer, and Active Job then refuses
    # to enqueue it. A guard that checked for a recipient that way broke every
    # email in production and, because failures are swallowed, did it quietly.
    test "does not touch the message, so a mailer with no recipient still enqueues cleanly" do
      assert_enqueued_emails 1 do
        assert Deliver.call(DepositMailer.with(order: build_order(contact_email: nil)).received).success?
      end
      # The job runs, the mailer returns NullMail, and nothing is delivered.
      assert_nothing_raised { perform_enqueued_jobs }
      assert_empty ActionMailer::Base.deliveries
    end

    test "a broken mail server is logged, never raised" do
      exploding = Object.new
      def exploding.deliver_later = raise(Net::SMTPServerBusy, "450 too many")

      result = nil
      assert_nothing_raised { result = Deliver.call(exploding) }
      assert result.failure?
      assert_equal :mail_error, result.code
    end
  end
end
