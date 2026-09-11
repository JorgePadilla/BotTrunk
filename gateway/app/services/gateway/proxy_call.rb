# frozen_string_literal: true

module Gateway
  # Forwards the caller's request to the service's upstream URL and times it.
  # Returns the upstream status, body and content type; never raises for
  # upstream failures.
  class ProxyCall
    OPEN_TIMEOUT = 5
    TIMEOUT = 60
    FORWARDED_HEADERS = %w[Content-Type Accept].freeze

    def initialize(service:, body:, headers: {}, connection: nil)
      @service = service
      @body = body
      @headers = headers
      @connection = connection || build_connection
    end

    def call
      return fulfil_locally if @service.built_in?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @connection.post(@service.upstream_url) do |req|
        FORWARDED_HEADERS.each { |h| req.headers[h] = @headers[h] if @headers[h] }
        req.headers["Content-Type"] ||= "application/json"
        req.body = @body
      end
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      data = { status: response.status, body: response.body, content_type: response.headers["Content-Type"], latency_ms: latency_ms }
      return Result.failure("upstream returned #{response.status}", code: :upstream_error, data: data) if response.status >= 500

      Result.success(data)
    rescue Faraday::Error => e
      Result.failure("upstream unreachable: #{e.message}", code: :upstream_unreachable)
    end

    private

    # BotTrunk's own services run in-process; same Result shape as a proxied call.
    def fulfil_locally
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      input = JSON.parse(@body.presence || "{}") rescue {}
      klass = @service.fulfiller.constantize
      args = { input: input }
      args[:service] = @service if klass.instance_method(:initialize).parameters.any? { |_, name| name == :service }
      result = klass.new(**args).call
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      result.success? ? Result.success(result.data.merge(latency_ms: latency_ms)) : Result.failure(result.error, code: result.code, data: result.data.merge(latency_ms: latency_ms))
    end

    def build_connection
      Faraday.new do |f|
        f.options.open_timeout = OPEN_TIMEOUT
        f.options.timeout = TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end
  end
end
