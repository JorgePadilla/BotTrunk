# frozen_string_literal: true

require "ipaddr"
require "resolv"

module Fulfillers
  # Built-in service: fetch a public page and return it as LLM-ready markdown.
  # Runs in-process (no upstream HTTP hop). Input: { url:, selector? }.
  # Output: { markdown:, title:, word_count: }. `render_js` is accepted and
  # ignored for now (documented as such).
  class ScrapeMarkdown
    MAX_BYTES = 2_000_000
    OPEN_TIMEOUT = 5
    TIMEOUT = 20
    STRIP = %w[script style noscript nav footer header aside form iframe svg template].freeze
    USER_AGENT = "BotTrunk/0.1 (+https://bottrunk.com/docs)"

    # DNS resolver used for the SSRF check; tests swap it for a fake.
    cattr_accessor :resolver, default: Resolv

    def initialize(input:, connection: nil)
      @input = input.is_a?(Hash) ? input : {}
      @connection = connection
    end

    def call
      url = @input["url"].to_s.strip
      uri = URI.parse(url) rescue nil
      return bad_request("url must be a public http(s) URL") unless uri.is_a?(URI::HTTP) && uri.host.present?
      return bad_request("url resolves to a private address") unless public_host?(uri.host)

      response = (@connection || build_connection).get(uri.to_s)
      return upstream_error("fetch failed with #{response.status}") unless response.success?
      return upstream_error("page too large") if response.body.bytesize > MAX_BYTES

      Result.success(status: 200, content_type: "application/json", body: extract(response.body).to_json)
    rescue Faraday::Error => e
      upstream_error("fetch failed: #{e.class.name.demodulize}")
    end

    private

    def extract(html)
      doc = Nokogiri::HTML(html)
      title = (doc.at("title")&.text || "").squish
      doc.css(STRIP.join(",")).remove
      scope = @input["selector"].present? ? doc.at_css(@input["selector"].to_s) : nil
      scope ||= doc.at("main") || doc.at("article") || doc.at("body") || doc
      markdown = ReverseMarkdown.convert(scope.to_html, unknown_tags: :bypass, github_flavored: true).strip
      markdown = markdown.gsub(/\n{3,}/, "\n\n")
      { markdown: markdown, title: title, word_count: markdown.split(/\s+/).count { |w| w.present? } }
    end

    def public_host?(host)
      addresses = self.class.resolver.getaddresses(host)
      return false if addresses.empty?

      addresses.all? do |a|
        ip = IPAddr.new(a)
        !(ip.private? || ip.loopback? || ip.link_local? || ip == IPAddr.new("0.0.0.0"))
      end
    rescue IPAddr::InvalidAddressError, Resolv::ResolvError
      false
    end

    def bad_request(msg) = Result.success(status: 422, content_type: "application/json", body: { error: msg }.to_json)
    def upstream_error(msg) = Result.failure(msg, code: :upstream_error, data: { status: 502, content_type: "application/json", body: { error: msg }.to_json })

    def build_connection
      Faraday.new(headers: { "User-Agent" => USER_AGENT, "Accept" => "text/html,application/xhtml+xml" }) do |f|
        f.response :follow_redirects, limit: 3
        f.options.open_timeout = OPEN_TIMEOUT
        f.options.timeout = TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end
  end
end
