# BotTrunk

**A pay-per-call marketplace for AI agents.** Agents buy API and human services with USDC over [x402](https://x402.org) on Algorand — no accounts, no API keys, no subscriptions. The payment is the credential.

Live at **[bottrunk.com](https://bottrunk.com)** · paid endpoints at `https://api.bottrunk.com/s/<slug>` · MainNet, settled by the [GoPlausible facilitator](https://facilitator.goplausible.xyz) · entered in the [Algorand Global x402 Challenge](https://algorand.co/global-x402-challenge) as a Composite entry.

## Try it in two minutes

Give Claude, Cursor or any MCP agent a wallet and a catalog of things it can buy:

```sh
npx bottrunk-mcp wallet          # creates ~/.bottrunk/wallet.json, prints the address
# send it a little USDC on Algorand (and ~0.2 ALGO once), then:
npx bottrunk-mcp wallet optin

claude mcp add bottrunk -- npx -y bottrunk-mcp     # Claude Code
# Claude Desktop / Cursor: { "mcpServers": { "bottrunk": { "command": "npx", "args": ["-y", "bottrunk-mcp"] } } }
```

Ask the agent *"what can you buy on BotTrunk?"* (free), then *"scrape https://example.com/pricing to markdown"* — it costs 0.09 USDC, paid from the agent's own wallet, and comes back with the transaction id. Details, caps and configuration in [`mcp-hub/README.md`](mcp-hub/README.md).

No MCP? Any x402 client works — Python, TypeScript or plain curl — see [bottrunk.com/docs](https://bottrunk.com/docs).

## How a paid call works

```
agent ──POST──▶ api.bottrunk.com/s/scrape-markdown ──▶ 402 + payment requirements (price, payTo, network)
agent ──POST + PAYMENT-SIGNATURE (signed USDC transfer)──▶ gateway ──/verify──▶ facilitator
                                                          gateway runs the service
                                                          gateway ──/settle──▶ facilitator ──▶ Algorand (USDC lands in the gateway wallet)
agent ◀── 200 + result + PAYMENT-RESPONSE receipt ◀── gateway records the 15/85 split in its ledger
```

Only the settle touches the chain. If the service fails, settle is never called and nothing is charged. The facilitator pays the network fee, so the agent spends USDC only. BotTrunk never holds keys or funds: the transfer goes from the payer straight to the receiving wallet, and the Rails app decides *whether* to do the work and keeps the books. Full picture with addresses: [`docs/money-flow.pdf`](docs/money-flow.pdf).

## What's in the catalog

| Service | Price | Status |
|---|---|---|
| **Pay someone in Honduras** — `deposit-bac-1000` … `-10000`: lempiras into any BAC Credomatic account, transferred by a person within 24 h, receipt reference returned | day's BCH rate + 5 % (≈ $42 for L1,000) | **live** |
| `scrape-markdown` — any public page as clean, LLM-ready markdown | 0.09 USDC | **live** |
| `page-metadata` — title, description, OpenGraph, favicon, feeds | 0.02 USDC | **live** |
| `extract-links` — every link, absolute, de-duplicated, internal vs external | 0.02 USDC | **live** |
| `url-health` — status, redirect chain, timings, TLS issuer and expiry | 0.02 USDC | **live** |
| `domain-dns` — A/AAAA/MX/NS/TXT/CNAME plus mail provider, SPF and DMARC hints | 0.03 USDC | **live** |
| `verify-business-hn` — a local visits the address, photographs it, checks the registry | 25 USDC | on request |
| `translate-es-en` — human translation and review, up to 1,000 words | 15 USDC | on request |

Every price is what the 402 asks for; the deposit tiers reprice hourly from the Banco Central de Honduras reference rate. Services marked *on request* are real work done by people — write to hello@bottrunk.com first; their endpoints answer 503 until then, so nothing can be charged by accident. Latency and success rates on the site are measured from settled calls, never estimated: a service with no traffic says so.

**Selling:** register any HTTP API with a price and BotTrunk hosts it behind the paywall; you collect USDC per call, we keep 15%. Early access at [bottrunk.com/sell](https://bottrunk.com/sell).

## Repository

```
gateway/     Rails 8.1 — catalog, x402 paywall + proxy, built-in fulfillers, ledger, public site
mcp-hub/     TypeScript — the `bottrunk-mcp` npm package (MCP server + agent wallet + spend caps)
docs/        architecture, ADRs, x402/Algorand facts, deploy runbook, challenge notes, money-flow diagram, lempira deposits runbook
```

Gateway design in one line: controllers are skinny, every business action is a service object returning a `Result`, only `app/services/payments/` knows about chains and facilitators, money is integer µUSDC everywhere. Read [`docs/architecture.md`](docs/architecture.md), then [`docs/x402-algorand.md`](docs/x402-algorand.md) for everything learned from the real facilitator (headers, v2 payload envelope, Bazaar discovery shape, gasless fee payer).

### Run it locally

```sh
cd gateway && bundle install && bin/setup && bin/dev      # http://localhost:3000, docs at /docs
bin/rails test                                             # whole paid loop with a fake adapter, no network

cd ../mcp-hub && npm install && npm test                   # real x402 client against an in-process fake gateway
```

More in [`gateway/README.md`](gateway/README.md) (TestNet payer wallet, `bin/pay`, `bin/send`).

## Status

- x402 endpoint live on Algorand MainNet with TLS, tagged `x402-global-challenge`, listed in the [Bazaar](https://facilitator.goplausible.xyz/discovery/resources) and on the [leaderboard](https://facilitator.goplausible.xyz/dashboard/leaderboards) as **BotTrunk**.
- `bottrunk-mcp` published to npm.
- Next: more real services, outside sellers, "pay with wallet" for humans, and the orchestration layer that routes an agent's budget across endpoints.

## Stack

Ruby 3.3 · Rails 8.1 · PostgreSQL · Propshaft · Tailwind v4 + daisyUI v5 · ViewComponent + Lookbook · Minitest + WebMock · Node 20 · `@modelcontextprotocol/sdk` · `@x402-avm/*` · algosdk · Render.

Conventions for contributors and AI assistants: [`CLAUDE.md`](CLAUDE.md). MIT.
