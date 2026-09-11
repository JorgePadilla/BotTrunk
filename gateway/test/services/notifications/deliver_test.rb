# frozen_string_literal: true

require "test_helper"

module Notifications
  class DeliverTest < ActiveSupport::TestCase
    test "enqueues a message that has a recipient" do
      assert_enqueued_emails 1 do
        assert Deliver.call(DepositMailer.with(order: build_order).received).success?
      end
    end

    test "a mailer that decided not to send is a success, not a failure" do
      assert_no_enqueued_emails do
        result = Deliver.call(DepositMailer.with(order: build_order(contact_email: nil)).received)

        assert result.success?
        assert_equal :no_recipient, result[:reason]
      end
    end

    test "a broken mail server is logged, never raised" do
      exploding = Object.new
      def exploding.to = [ "someone@example.com" ]
      def exploding.deliver_later = raise(Net::SMTPServerBusy, "450 too many")
      def exploding.try(_) = "Exploding mail"

      result = nil
      assert_nothing_raised { result = Deliver.call(exploding) }
      assert result.failure?
      assert_equal :mail_error, result.code
    end
  end
end
