# frozen_string_literal: true

require "test_helper"

module Notifications
  class AnnounceOrderTest < ActiveSupport::TestCase
    test "a settled deposit tells the queue owner and the buyer" do
      with_admin_email do
        assert_enqueued_emails 2 do
          AnnounceOrder.new(order: build_order).call
        end
      end
    end

    test "an agent with no inbox only costs us the admin alert" do
      with_admin_email do
        assert_enqueued_emails 1 do
          AnnounceOrder.new(order: build_order(contact_email: nil)).call
        end
      end
    end

    test "with no ADMIN_EMAIL and no buyer address, nothing is sent at all" do
      with_admin_email(nil) do
        assert_no_enqueued_emails do
          AnnounceOrder.new(order: build_order(contact_email: nil)).call
        end
      end
    end

    test "delivering emails the buyer, refunding emails the buyer, cancelling says nothing" do
      order = build_order
      assert_enqueued_emails(1) { order.deliver!(receipt_reference: "BAC-1"); AnnounceOrderUpdate.new(order: order).call }

      refunded = build_order
      refunded.refund!(transaction_id: "TX")
      assert_enqueued_emails(1) { AnnounceOrderUpdate.new(order: refunded).call }

      cancelled = build_order(status: "cancelled")
      assert_no_enqueued_emails { AnnounceOrderUpdate.new(order: cancelled).call }
    end
  end
end
