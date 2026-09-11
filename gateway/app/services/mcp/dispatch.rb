# frozen_string_literal: true

module Mcp
  # A JSON-RPC 2.0 dispatcher for the Streamable HTTP transport, in the small
  # subset a tools-only server needs: initialize, ping, tools/list, tools/call.
  #
  # Stateless on purpose. The 2026-07-28 revision removed protocol-level
  # sessions and the GET stream, and everything we expose answers in one round
  # trip, so there is nothing to keep between requests: no session ids, no SSE.
  # Older clients (2025-03-26 … 2025-11-25) still begin with `initialize`, so
  # that method is answered too, and their `Mcp-Session-Id` header is ignored.
  #
  # Returns [http_status, body_hash_or_nil]; a notification answers 202 with
  # no body, per the transport spec.
  class Dispatch
    SUPPORTED_VERSIONS = %w[2024-11-05 2025-03-26 2025-06-18 2025-11-25 2026-07-28].freeze
    SERVER_VERSION = "0.1.0"
    LATEST_VERSION = SUPPORTED_VERSIONS.last

    PARSE_ERROR = -32_700
    INVALID_REQUEST = -32_600
    METHOD_NOT_FOUND = -32_601
    INVALID_PARAMS = -32_602
    INTERNAL_ERROR = -32_603

    INSTRUCTIONS = <<~TEXT.strip
      BotTrunk is a marketplace where agents buy services per call with USDC over x402 on Algorand — data
      utilities, and work done by people (a bank deposit in Honduras, delivered within 24 hours with the
      receipt). These tools are free and read-only: they tell you what exists, what it costs right now and
      how an order is going. This server cannot spend money for you, because it does not hold your key.
      To actually buy: call bottrunk_payment_instructions and pay the endpoint's HTTP 402 with your own
      wallet, or run `npx bottrunk-mcp` on the machine you control and the payment is handled for you.
    TEXT

    def initialize(payload, version_header: nil)
      @payload = payload
      @version_header = version_header
    end

    def call
      return [ 400, error_body(nil, INVALID_REQUEST, "Batched requests are not supported; send one JSON-RPC message per POST.") ] if @payload.is_a?(Array)
      return [ 400, error_body(nil, INVALID_REQUEST, "Expected a JSON-RPC object.") ] unless @payload.is_a?(Hash)

      id = @payload["id"]
      method = @payload["method"].to_s
      params = @payload["params"] || {}

      # A notification (no id) is acknowledged and dropped: nothing we expose
      # needs one, and the spec wants 202 with an empty body.
      return [ 202, nil ] if id.nil?

      case method
      when "initialize" then ok(id, initialize_result(params))
      when "ping" then ok(id, {})
      when "tools/list" then ok(id, { tools: Tools.list })
      when "tools/call" then tool_call(id, params)
      when "" then [ 400, error_body(id, INVALID_REQUEST, "Missing method.") ]
      else
        [ 200, error_body(id, METHOD_NOT_FOUND, "BotTrunk exposes tools only; #{method} is not implemented.") ]
      end
    end

    # The tool name of a tools/call, for logging and the Mcp-Name header check.
    def tool_name = @payload.is_a?(Hash) ? @payload.dig("params", "name") : nil

    def method_name = @payload.is_a?(Hash) ? @payload["method"] : nil

    private

    def initialize_result(params)
      requested = params["protocolVersion"].presence
      {
        protocolVersion: SUPPORTED_VERSIONS.include?(requested) ? requested : LATEST_VERSION,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "bottrunk", title: "BotTrunk", version: SERVER_VERSION, websiteUrl: "https://bottrunk.com" },
        instructions: INSTRUCTIONS
      }
    end

    def tool_call(id, params)
      name = params["name"].to_s
      return [ 200, error_body(id, INVALID_PARAMS, "tools/call needs a tool name.") ] if name.blank?

      ok(id, Tools.call(name, params["arguments"]))
    end

    def ok(id, result) = [ 200, { jsonrpc: "2.0", id: id, result: result } ]

    def error_body(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end
  end
end
