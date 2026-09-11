# frozen_string_literal: true

module Analytics
  # Records one Event. Never raises: analytics must not break a request, so
  # any problem becomes a logged failure Result.
  #
  # Privacy by construction: the IP and user agent are only used to derive a
  # `visitor` token that rotates daily (SHA-256 of ip + ua + date + secret,
  # truncated) and a coarse location (country + city, via a local GeoIP
  # database), and the user agent collapses to a coarse `client` label.
  class Track
    BOT_UA = /bot|crawl|spider|slurp|preview|fetch\b|monitor|headless/i

    def initialize(name:, path: nil, referrer: nil, user_agent: nil, ip: nil, service_slug: nil, properties: {}, now: Time.current)
      @name = name
      @path = path
      @referrer = referrer
      @user_agent = user_agent.to_s
      @ip = ip.to_s
      @service_slug = service_slug
      @properties = properties
      @now = now
    end

    def call
      location = Geolocate.call(@ip) || {}
      event = Event.create!(
        name: @name,
        country: location[:country],
        city: location[:city],
        path: @path&.truncate(200),
        referrer_host: referrer_host,
        client: self.class.classify(@user_agent),
        visitor: visitor,
        service_slug: @service_slug,
        properties: @properties,
        created_at: @now
      )
      Result.success(event: event)
    rescue StandardError => e
      Rails.logger.warn("analytics: #{@name} not recorded: #{e.class}: #{e.message}")
      Result.failure(e.message, code: :analytics_error)
    end

    # Coarse client label from a user agent. Order matters: our own MCP server
    # and x402 libraries first, then generic HTTP tools, then browsers.
    def self.classify(user_agent)
      ua = user_agent.to_s
      return "other" if ua.blank?
      return "bottrunk-mcp" if ua.start_with?("bottrunk-mcp")
      return "x402-client" if ua.match?(/x402/i)
      return "bot" if ua.match?(BOT_UA)
      return "curl" if ua.start_with?("curl/")
      return "python" if ua.match?(/python|httpx|aiohttp/i)
      return "node" if ua.match?(/node|undici|axios/i)
      return "browser" if ua.match?(/Mozilla|Safari|Chrome|Firefox|Edg/)

      "other"
    end

    private

    def referrer_host
      return nil if @referrer.blank?

      host = URI.parse(@referrer).host
      host&.delete_prefix("www.")
    rescue URI::InvalidURIError
      nil
    end

    def visitor
      return nil if @ip.blank? && @user_agent.blank?

      secret = Rails.application.secret_key_base.to_s
      Digest::SHA256.hexdigest([ @ip, @user_agent, @now.utc.to_date.iso8601, secret ].join("|"))[0, 16]
    end
  end
end
