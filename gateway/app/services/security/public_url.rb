# frozen_string_literal: true

require "ipaddr"
require "resolv"

module Security
  # One place that decides whether a URL is safe to make a request to.
  #
  # It lives here rather than inside `Fulfillers::Base` because two different
  # layers need the same answer: the services that fetch a URL right now, and
  # the seller form that records a URL we will fetch later. A private address
  # accepted at registration is an SSRF that arrives on a delay.
  class PublicUrl
    # Swapped for a fake in tests; `Fulfillers::Base.resolver` delegates here
    # so the existing test hook keeps working.
    cattr_accessor :resolver, default: Resolv

    # Returns [uri, nil] on success, or [nil, :not_http | :private |
    # :unresolvable] on refusal.
    #
    # `strict_dns:` decides what an unresolvable host means. For a request we
    # are about to make it means refuse — we could not check it, so we do not
    # trust it. For a URL someone is registering it means allow: people list
    # endpoints before they point DNS at them, and refusing that is worse than
    # useless.
    def self.parse(raw, strict_dns: true)
      uri = begin
        URI.parse(raw.to_s.strip)
      rescue URI::InvalidURIError
        nil
      end
      return [ nil, :not_http ] unless uri.is_a?(URI::HTTP) && uri.host.present?

      addresses = resolve(uri.host)
      return strict_dns ? [ nil, :unresolvable ] : [ uri, nil ] if addresses.empty?
      return [ nil, :private ] unless addresses.all? { |a| public_address?(a) }

      [ uri, nil ]
    end

    def self.resolve(host)
      resolver.getaddresses(host)
    rescue Resolv::ResolvError
      []
    end

    def self.public_address?(address)
      ip = IPAddr.new(address)
      !(ip.private? || ip.loopback? || ip.link_local? || ip == IPAddr.new("0.0.0.0"))
    rescue IPAddr::InvalidAddressError
      false
    end
  end
end
