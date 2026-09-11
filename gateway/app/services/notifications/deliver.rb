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
  # **Nothing here may touch the message.** Reading `mail.to` processes the
  # mailer, and Active Job then refuses to enqueue it — "you've accessed the
  # message before asking to deliver it later" — because only the mailer's
  # *arguments* travel with the job, so any change made here would be silently
  # lost. A guard that read the recipient to check there was one broke every
  # email in production, and the rescue below meant it did so quietly. Whether
  # there is anyone to write to is decided by the caller, from the record,
  # before the mail is built.
  class Deliver
    def initialize(mail:)
      @mail = mail
    end

    def self.call(mail) = new(mail: mail).call

    def call
      @mail.deliver_later
      Result.success(sent: true)
    rescue StandardError => e
      Rails.logger.error("mail: could not enqueue #{@mail.class.name}: #{e.class}: #{e.message}")
      Result.failure(e.message, code: :mail_error)
    end
  end
end
