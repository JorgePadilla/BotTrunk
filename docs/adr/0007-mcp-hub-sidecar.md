# ADR 0007 — The MCP hub is a stateless TypeScript sidecar

**Status:** accepted · **Date:** 2026-09-02

## Context
Demand is the scarce side: agents must be able to discover and pay for services from inside Claude, GPT and LangChain. The MCP ecosystem's reference SDK and x402 client libraries are TypeScript.

## Decision
`mcp-hub/` is a small TypeScript MCP server that reads the gateway's `GET /api/v1/catalog`, exposes one tool per endpoint, and performs the x402 flow with the agent's configured wallet. It has no database and no secrets of its own.

## Consequences
- The Rails app stays the single source of truth; the hub can be redeployed or replaced freely.
- Two languages in the repo, but the TypeScript surface is a few hundred lines.
- The catalog JSON API is a public contract from Phase 1 on.
