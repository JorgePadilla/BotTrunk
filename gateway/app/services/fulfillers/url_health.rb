# frozen_string_literal: true

require "socket"
require "openssl"

module Fulfillers
  # Built-in service: is this URL alive, where does it end up, and when does
  # its certificate expire. One call gives an agent the status code, the full
  # redirect chain with timings, the response headers that matter and the TLS
  # expiry — the checks a human would run before trusting a link.
  # Input: { url }. Output: { ok, status, final_url, redirects, response_ms, tls, headers }.
  class UrlHealth < Base
    MAX_HOPS = 5
    REDIRECTS = [ 301, 302, 303, 307, 308 ].freeze
    KEEP_HEADERS = %w[content-type server content-length last-modified cache-control x-powered-by].freeze

    # Test hook: ->(host, port) { { issuer:, expires_at:, days_left: } } or nil.
    cattr_accessor :tls_prober, default: nil

    def call
      uri = public_uri { |failure| return failure }

      hops = []
      current = uri
      response = nil
      MAX_HOPS.times do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = plain.get(current.to_s)
        ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        hops << { url: current.to_s, status: response.status, response_ms: ms }
        location = response.headers["location"]
        break unless REDIRECTS.include?(response.status) && location.present?

        current = begin
          URI.join(current, location)
        rescue URI::Error
          break
        end
        break unless current.is_a?(URI::HTTP)
      end

      json({
        url: uri.to_s,
        final_url: hops.last[:url],
        ok: response.status < 400,
        status: response.status,
        response_ms: hops.sum { |h| h[:response_ms] },
        redirects: hops.size - 1,
        chain: (hops if hops.size > 1),
        headers: response.headers.to_h.slice(*KEEP_HEADERS).presence,
        tls: tls_for(URI.parse(hops.last[:url])),
        checked_at: Time.current.utc.iso8601
      }.compact)
    rescue Faraday::Error => e
      json({ url: input["url"].to_s, ok: false, error: e.message.truncate(120), checked_at: Time.current.utc.iso8601 })
    end

    private

    def plain
      @plain ||= build_connection(follow: false, accept: "*/*")
    end

    def tls_for(uri)
      return nil unless uri.scheme == "https"

      prober = tls_prober || method(:probe)
      prober.call(uri.host, uri.port)
    end

    # Opens one TLS connection just to read the certificate. Any failure is
    # reported as nil rather than failing the whole check.
    def probe(host, port)
      tcp = Socket.tcp(host, port, connect_timeout: OPEN_TIMEOUT)
      ssl = OpenSSL::SSL::SSLSocket.new(tcp, OpenSSL::SSL::SSLContext.new)
      ssl.hostname = host
      ssl.connect
      cert = ssl.peer_cert
      {
        issuer: cert.issuer.to_a.find { |k, _v, _t| k == "O" }&.at(1) || cert.issuer.to_s,
        expires_at: cert.not_after.utc.iso8601,
        days_left: ((cert.not_after - Time.current) / 86_400).floor
      }
    rescue StandardError => e
      Rails.logger.info("url-health: tls probe failed for #{host}: #{e.class}")
      nil
    ensure
      begin
        ssl&.close
      rescue StandardError
        nil
      end
      begin
        tcp&.close
      rescue StandardError
        nil
      end
    end
  end
end
