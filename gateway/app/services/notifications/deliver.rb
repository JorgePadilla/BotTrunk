# frozen_string_literal: true

module Notifications
  # Hands a message to Active Job and swallows anything that goes wrong.
  #
  # Email is never allowed to break the thing that triggered it: a settled
  # payment is on-chain and irreversible long before we try to tell anyone
  # about it, and a mail server having a bad afternoon must not turn that into
  # an error for the payer. Failures are logged; the ledger and the order are
  # the record of truth.
  #
  # A mailer that decided not to send (no recipient) returns an
  # ActionMailer::Base::NullMail, which has nothing to deliver — that is a
  # success here, not a failure.
  class Deliver
    def initialize(mail:)
      @mail = mail
    end

    def self.call(mail) = new(mail: mail).call

    def call
      return Result.success(sent: false, reason: :no_recipient) unless deliverable?

      @mail.deliver_later
      Result.success(sent: true)
    rescue StandardError => e
      Rails.logger.error("mail: could not enqueue #{describe}: #{e.class}: #{e.message}")
      Result.failure(e.message, code: :mail_error)
    end

    private

    def deliverable? = @mail.respond_to?(:to) && @mail.to.present?

    def describe = @mail.try(:subject).presence || @mail.class.name
  end
end
