# frozen_string_literal: true

module Notifications
  # A paid call settled. Unlike a deposit, nobody has to *do* anything about
  # it — the alert exists so the operator learns the moment a wallet that is
  # not theirs starts paying, which is the only signal that matters before
  # there are customers.
  #
  # `first_from_payer` is computed here, not in the mailer, because it is a
  # question about the ledger and the mailer should not query.
  class AnnounceCall
    def initialize(call:)
      @call = call
    end

    def call
      return Result.success(sent: false) if @call.blank? || ApplicationMailer.admin_address.blank?

      Deliver.call(AdminMailer.with(call: @call, first_from_payer: first_from_payer?).call_settled)
      Result.success(sent: true)
    end

    private

    # First call ever from this wallet — this row included, so the count is 1.
    # An unknown payer (the facilitator did not report one) is never "new":
    # we cannot tell one anonymous caller from another.
    def first_from_payer?
      return false if @call.payer_address.blank?

      Call.where(payer_address: @call.payer_address).count == 1
    end
  end
end
