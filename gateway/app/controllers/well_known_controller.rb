# frozen_string_literal: true

# The agent-readable files the x402 facilitator probes at our origin, plus the
# ones coding agents read straight from the domain. Every one is rendered from
# `Catalog::Service`, so a price here can never disagree with the 402 the
# endpoint actually answers — the whole point of publishing them.
#
# Serving rules the facilitator enforces (guide/discovery): status 200, real
# JSON, never the HTML 404 page. Rails' SPA-less routing gives us that for
# free as long as these routes exist.
class WellKnownController < ApplicationController
  DESCRIPTION = "Services an AI agent can buy on its own, paid per call in USDC over x402 on Algorand. " \
                "Data utilities and work done by real people. No accounts, no API keys, no subscriptions."

  # A static index of the paid endpoints, for agents that want prices before
  # spending a request to discover them.
  def x402
    render json: {
      x402Version: 2,
      name: "BotTrunk",
      description: DESCRIPTION,
      resources: live_services.map do |service|
        {
          url: service.endpoint_url,
          method: "POST",
          description: service.summary,
          network: net[:caip2],
          asset: net[:usdc_asa],
          amount: service.price_atomic.to_s,
          payTo: pay_to
        }
      end
    }
  end

  # A2A agent card: one skill per paid endpoint.
  def agent_card
    render json: {
      name: "BotTrunk",
      description: DESCRIPTION,
      url: "https://bottrunk.com",
      version: "1.0.0",
      capabilities: { streaming: false },
      defaultInputModes: [ "text" ],
      defaultOutputModes: [ "text" ],
      skills: live_services.map do |service|
        {
          id: service.slug,
          name: service.name,
          description: "#{service.summary} Paid per call via x402 (#{price(service)} USDC).",
          tags: [ "x402", "algorand", service.category.downcase ].uniq
        }
      end
    }
  end

  def agent_manifest
    render json: {
      name: "BotTrunk",
      description: DESCRIPTION,
      url: "https://bottrunk.com",
      documentation: "https://bottrunk.com/llms.txt",
      payments: { protocol: "x402", network: "algorand", asset: "USDC" }
    }
  end

  # MCP manifest for the hosted endpoint. Streamable HTTP, not SSE — it is
  # stateless POST-only (docs/architecture.md §6c). `tools` is what that server
  # really answers: the free, read-only ones. A remote server cannot hold an
  # agent's wallet, so the paid tools run in the local package; they are listed
  # under `paidTools` with how to get them, not advertised as if this endpoint
  # could run them.
  def mcp
    render json: {
      name: "BotTrunk MCP",
      description: "Free, read-only MCP server for BotTrunk's catalog: what is for sale, what it costs and how to pay. " \
                   "To buy, run the local server (npx -y bottrunk-mcp), which pays from the agent's own Algorand wallet.",
      version: "1.0.0",
      transport: { type: "streamable-http", url: "https://mcp.bottrunk.com/mcp" },
      tools: Mcp::Tools.list.map { |tool| tool.slice(:name, :description) },
      paidTools: {
        package: "bottrunk-mcp",
        command: "npx -y bottrunk-mcp",
        tools: live_services.map do |service|
          { name: service.tool_name, description: "#{service.summary} #{price(service)} USDC per call." }
        end
      }
    }
  end

  # Operating instructions for agents already using us. The facilitator does
  # not index this one; coding agents read it from the domain like llms.txt.
  def agents
    render plain: render_to_string(template: "well_known/agents", formats: [ :text ], layout: false),
           content_type: "text/markdown"
  end

  private

  def live_services = Catalog::Service.all.select(&:live?)

  def net = Payments::Networks.algorand(Rails.configuration.x402.network)

  def pay_to = Rails.configuration.x402.pay_to

  # Exact USDC, as many decimals as the price needs: "0.002", not "0.00".
  def price(service) = helpers.usdc(service.price_atomic).delete_prefix("$")
end
