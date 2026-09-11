# frozen_string_literal: true

require "resolv"

module Fulfillers
  # Built-in service: the DNS record set of a domain in one call — A, AAAA,
  # MX, NS, TXT, CNAME — plus a guess at the mail and verification providers
  # the TXT/MX records give away. Useful to an agent checking whether a
  # company is real, who hosts it, and where its mail goes.
  # Input: { domain }. Output: { domain, a, aaaa, mx, ns, txt, cname, hints }.
  class DomainDns < Base
    HOSTNAME = /\A(?=.{1,253}\z)([a-z0-9](-?[a-z0-9])*\.)+[a-z]{2,}\z/
    MAIL_PROVIDERS = {
      /google|googlemail/ => "Google Workspace", /outlook|microsoft/ => "Microsoft 365", /zoho/ => "Zoho Mail",
      /protonmail|proton\.me/ => "Proton Mail", /mailgun/ => "Mailgun", /sendgrid/ => "SendGrid",
      /amazonses|amazonaws/ => "Amazon SES", /titan|hostinger/ => "Titan", /icloud/ => "iCloud Mail"
    }.freeze

    # Test hook: an object answering #getresources(name, type), like Resolv::DNS.
    cattr_accessor :dns_client, default: nil

    def call
      domain = normalize(input["domain"])
      return bad_request("domain must be a hostname like example.com") unless domain&.match?(HOSTNAME)

      records = resolve(domain)
      return upstream_error("DNS lookup failed for #{domain}") if records.nil?

      json(records.merge(domain: domain, checked_at: Time.current.utc.iso8601, hints: hints(records)).compact)
    end

    private

    def normalize(value)
      host = value.to_s.strip.downcase.sub(%r{\Ahttps?://}, "").split("/").first.to_s.delete_suffix(".")
      host.presence
    end

    def resolve(domain)
      with_dns do |dns|
        {
          a: dns.getresources(domain, Resolv::DNS::Resource::IN::A).map { |r| r.address.to_s },
          aaaa: dns.getresources(domain, Resolv::DNS::Resource::IN::AAAA).map { |r| r.address.to_s },
          mx: dns.getresources(domain, Resolv::DNS::Resource::IN::MX).map { |r| { preference: r.preference, exchange: r.exchange.to_s } }.sort_by { |m| m[:preference] },
          ns: dns.getresources(domain, Resolv::DNS::Resource::IN::NS).map { |r| r.name.to_s },
          txt: dns.getresources(domain, Resolv::DNS::Resource::IN::TXT).map { |r| r.strings.join },
          cname: dns.getresources(domain, Resolv::DNS::Resource::IN::CNAME).map { |r| r.name.to_s }.first
        }
      end
    rescue Resolv::ResolvError, Timeout::Error, IOError => e
      Rails.logger.info("domain-dns: #{e.class}: #{e.message}")
      nil
    end

    def with_dns(&block)
      return block.call(dns_client) if dns_client

      Resolv::DNS.open do |dns|
        dns.timeouts = [ 3, 2 ]
        block.call(dns)
      end
    end

    def hints(records)
      hints = {}
      exchange = records[:mx].map { |m| m[:exchange] }.join(" ").downcase
      MAIL_PROVIDERS.each { |pattern, name| hints[:email] ||= name if exchange.match?(pattern) }
      spf = records[:txt].find { |t| t.start_with?("v=spf1") }
      hints[:spf] = spf if spf
      hints[:dmarc] = true if records[:txt].any? { |t| t.start_with?("v=DMARC1") }
      hints[:verifications] = records[:txt].filter_map { |t| t[/\A([a-z0-9-]+?)-(?:site|domain)-verification/, 1] }.uniq.presence
      hints.compact.presence
    end
  end
end
