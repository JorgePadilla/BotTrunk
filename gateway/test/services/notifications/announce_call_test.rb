# frozen_string_literal: true

require "test_helper"

module Notifications
  class AnnounceCallTest < ActiveSupport::TestCase
    test "a settled call alerts the operator" do
      with_admin_email do
        assert_enqueued_emails 1 do
          AnnounceCall.new(call: build_call).call
        end
      end
    end

    test "with no ADMIN_EMAIL there is nobody to alert and nothing is built" do
      with_admin_email(nil) do
        assert_no_enqueued_emails { AnnounceCall.new(call: build_call).call }
      end
    end

    test "the first call from a wallet says so; the second does not" do
      with_admin_email do
        perform_enqueued_jobs { AnnounceCall.new(call: build_call(payer_address: PAYER)).call }
        assert_match(/\ANew payer —/, ActionMailer::Base.deliveries.last.subject)

        perform_enqueued_jobs { AnnounceCall.new(call: build_call(payer_address: PAYER)).call }
        assert_match(/\APaid call —/, ActionMailer::Base.deliveries.last.subject)
      end
    end

    # An anonymous payer is not a new customer — we cannot tell one from another.
    test "a call with no payer address is never announced as a new payer" do
      with_admin_email do
        perform_enqueued_jobs { AnnounceCall.new(call: build_call(payer_address: nil)).call }
        assert_match(/\APaid call —/, ActionMailer::Base.deliveries.last.subject)
      end
    end

    test "the subject carries the service and the amount, because that is all a phone shows" do
      with_admin_email do
        perform_enqueued_jobs { AnnounceCall.new(call: build_call(service_slug: "extract-links", amount: 20_000)).call }
      end

      subject = ActionMailer::Base.deliveries.last.subject
      assert_includes subject, "extract-links"
      assert_includes subject, "$0.02"
    end

    test "the body links the transaction and names both sides of the split" do
      with_admin_email do
        perform_enqueued_jobs { AnnounceCall.new(call: build_call).call }
      end

      body = ActionMailer::Base.deliveries.last.body.encoded
      assert_includes body, "allo.info/tx/TXN123"
      assert_includes body, "0.0015"  # commission
    end

    PAYER = "LQAWG3WUMKWTFGEFCCOET6JGPRKD2JFYPIJ6HPIRYAC6QDUJSBDVMCKPFQ"

    private

    def build_call(**overrides)
      Call.create!({
        service_slug: "scrape-markdown", pay_to: X402Helpers::TEST_PAY_TO,
        network: "algorand:wGHE2Pwdvd7S12BL5FaOP20EGYesN73ktiC1qzkkit8=", asset: "31566704",
        amount: 10_000, commission: 1_500, seller_amount: 8_500,
        payer_address: PAYER, transaction_id: "TXN#{Call.count + 123}", status: "settled"
      }.merge(overrides))
    end
  end
end
