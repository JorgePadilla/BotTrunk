# frozen_string_literal: true

require "base64"

module Fulfillers
  # Shared pipeline for the two services that hand back a rendered file:
  # `screenshot-url` (PNG) and `pdf-url` (PDF). Both guard the URL, drive one
  # Cloudflare Browser Rendering action and wrap the bytes; only the action,
  # the format and the browser options differ, so subclasses fill those in.
  #
  # The bytes come back base64 inside JSON rather than as a raw body, because
  # the 402 advertises `application/json` and the Bazaar schema describes an
  # object. Base64 costs a third more, which is why the cap below is tighter
  # than the renderer's own 8 MB: a refusal is free, a 10 MB JSON body is not.
  class RenderedCapture < Base
    MAX_RENDER_BYTES = 1_500_000
    RETRY_ON = /answered 429/

    # Test hook: the pause before the single retry, in seconds.
    cattr_accessor :retry_delay, default: 1.5

    def call
      uri = public_uri { |failure| return failure }

      bytes, problem = render(uri)
      return upstream_error(problem) if problem
      return upstream_error("renderer returned an empty #{format}") if bytes.blank?
      return too_large(bytes) if bytes.bytesize > MAX_RENDER_BYTES

      json(payload(bytes).merge(url: uri.to_s, bytes: bytes.bytesize, captured_at: Time.current.utc.iso8601))
    end

    private

    # The free tier runs one browser at a time, so a burst answers 429. One
    # retry covers a neighbour's render finishing; past that we fail, and a
    # failure is never settled.
    def render(uri)
      bytes, problem = capture(uri)
      return [ bytes, nil ] if problem.nil?
      return [ nil, problem ] unless problem.match?(RETRY_ON)

      sleep(retry_delay) if retry_delay.to_f.positive?
      capture(uri)
    end

    def capture(uri)
      Rendering::Cloudflare.new(action: action, url: uri.to_s, options: render_options).call
    end

    # A 4xx, so the buyer is not charged for a file we refuse to send.
    def too_large(bytes)
      bad_request("rendered #{format} is #{(bytes.bytesize / 1_000_000.0).round(1)} MB, over the #{(MAX_RENDER_BYTES / 1_000_000.0).round(1)} MB limit")
    end

    def wait_for
      selector = input["wait_for"].to_s.strip
      selector.present? ? { waitForSelector: selector } : {}
    end
  end
end
