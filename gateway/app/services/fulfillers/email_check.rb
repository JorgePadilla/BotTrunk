# frozen_string_literal: true

require "resolv"

module Fulfillers
  # Built-in service: what can be told about an email address without sending
  # anything to it — syntax, whether the domain can receive mail at all, and
  # whether it is a disposable, free or role address.
  #
  # Deliberately not a "does this mailbox exist" check. That needs an SMTP
  # probe, which is rude, unreliable and gets the prober blocked; the page
  # says so rather than implying a stronger answer than we have.
  # Input: { email }. Output: { email, valid_syntax, domain, mx, deliverable, … }.
  class EmailCheck < Base
    SYNTAX = /\A[a-z0-9!\#$%&'*+\/=?^_`{|}~-]+(\.[a-z0-9!\#$%&'*+\/=?^_`{|}~-]+)*@((?=.{1,253}\z)([a-z0-9](-?[a-z0-9])*\.)+[a-z]{2,})\z/
    DISPOSABLE = %w[
      mailinator.com guerrillamail.com sharklasers.com 10minutemail.com yopmail.com temp-mail.org
      tempmail.com trashmail.com dispostable.com getnada.com maildrop.cc throwawaymail.com
      fakeinbox.com mytemp.email moakt.com emailondeck.com mohmal.com spamgourmet.com
    ].to_set.freeze
    FREE = %w[
      gmail.com googlemail.com yahoo.com ymail.com outlook.com hotmail.com live.com msn.com
      icloud.com me.com aol.com gmx.com gmx.net proton.me protonmail.com yandex.com zoho.com mail.com
    ].to_set.freeze
    ROLE = %w[
      admin administrator info support sales billing accounts contact help hello noreply no-reply
      postmaster webmaster abuse security team office hr jobs careers marketing
    ].to_set.freeze

    # Test hook: an object answering #getresources(name, type), like Resolv::DNS.
    cattr_accessor :dns_client, default: nil

    def call
      email = input["email"].to_s.strip.downcase
      return bad_request("email must be an address like name@example.com") if email.blank? || email.length > 254

      match = SYNTAX.match(email)
      return json(report(email, nil, nil)) if match.nil?

      domain = match[2]
      mx = mail_hosts(domain)
      return upstream_error("DNS lookup failed for #{domain}") if mx.nil?

      json(report(email, domain, mx))
    end

    private

    def report(email, domain, mx)
      local = email.split("@").first.to_s
      {
        email: email,
        valid_syntax: domain.present?,
        domain: domain,
        mx: mx&.map { |m| m[:exchange] },
        deliverable_domain: mx.present?,
        disposable: domain ? DISPOSABLE.include?(domain) : nil,
        free_provider: domain ? FREE.include?(domain) : nil,
        role_account: domain ? ROLE.include?(local.split("+").first.to_s) : nil,
        checked_at: Time.current.utc.iso8601,
        note: "Syntax, DNS and list checks only. No mail was sent and no mailbox was probed."
      }.compact
    end

    # A domain with no MX but an A record still accepts mail, per RFC 5321,
    # so that counts as deliverable — with the implicit host named.
    def mail_hosts(domain)
      with_dns do |dns|
        mx = dns.getresources(domain, Resolv::DNS::Resource::IN::MX)
               .map { |r| { preference: r.preference, exchange: r.exchange.to_s.delete_suffix(".") } }
               .sort_by { |m| m[:preference] }
        next mx if mx.any?

        dns.getresources(domain, Resolv::DNS::Resource::IN::A).any? ? [ { preference: 0, exchange: domain } ] : []
      end
    rescue Resolv::ResolvError, Timeout::Error, IOError => e
      Rails.logger.info("email-check: #{e.class}: #{e.message}")
      nil
    end

    def with_dns(&block)
      return block.call(dns_client) if dns_client

      Resolv::DNS.open do |dns|
        dns.timeouts = [ 3, 2 ]
        block.call(dns)
      end
    end
  end
end
