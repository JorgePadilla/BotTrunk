# frozen_string_literal: true

# The hosted MCP endpoint (mcp.bottrunk.com/mcp, and /mcp on every host).
#
# Streamable HTTP, stateless, JSON responses only — no SSE, no sessions, so a
# single Rails request answers a whole JSON-RPC message. Everything it exposes
# is free and read-only; see Mcp::Tools for why a remote server cannot pay.
class McpController < ActionController::API
  include TracksEvents

  before_action :cors_headers

  def create
    payload = parse_body or return render(json: { jsonrpc: "2.0", id: nil, error: { code: Mcp::Dispatch::PARSE_ERROR, message: "Invalid JSON." } }, status: :bad_request)

    dispatch = Mcp::Dispatch.new(payload, version_header: request.headers["MCP-Protocol-Version"])
    status, body = dispatch.call
    track(dispatch)

    return head(:accepted) if body.nil?

    render json: body, status: status
  end

  # This revision has no GET stream and no session to delete; say so plainly
  # rather than leaving an old client waiting on an SSE connection.
  def unsupported
    response.set_header("Allow", "POST, OPTIONS")
    render json: { jsonrpc: "2.0", id: nil, error: { code: Mcp::Dispatch::INVALID_REQUEST, message: "BotTrunk's MCP endpoint is POST-only (stateless Streamable HTTP)." } },
           status: :method_not_allowed
  end

  def preflight = head(:no_content)

  private

  def parse_body
    raw = request.raw_post
    return nil if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end

  def track(dispatch)
    return unless dispatch.method_name == "tools/call"

    track_event("mcp_call", service_slug: dispatch.tool_name, tool: dispatch.tool_name)
  end

  def cors_headers
    response.set_header("Access-Control-Allow-Origin", "*")
    response.set_header("Access-Control-Allow-Methods", "POST, OPTIONS")
    response.set_header("Access-Control-Allow-Headers", "Content-Type, Accept, MCP-Protocol-Version, Mcp-Method, Mcp-Name, Mcp-Session-Id, Authorization")
    response.set_header("Access-Control-Expose-Headers", "MCP-Protocol-Version")
    response.set_header("Access-Control-Max-Age", "86400")
  end
end
