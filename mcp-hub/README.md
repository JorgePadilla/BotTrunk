# bottrunk-mcp

Give Claude, Cursor, or any MCP-speaking agent a wallet and a catalog of things it can buy.

`bottrunk-mcp` is an [MCP](https://modelcontextprotocol.io) server that exposes every live [BotTrunk](https://bottrunk.com) service as a tool. When the agent calls one, the server answers the gateway's HTTP 402 with a USDC transfer signed by **the agent's own Algorand wallet**, retries, and hands the result back. No API keys, no accounts, no subscriptions — the payment is the credential.

- Pay-per-call in USDC on Algorand over [x402](https://x402.org), settled by the GoPlausible facilitator (gasless: the facilitator pays the network fee).
- The key never leaves your machine. It lives in `~/.bottrunk/wallet.json` (mode 0600) or in `BOTTRUNK_MNEMONIC`.
- Spending caps before anything is signed: per call and per UTC day.
- Free tools for discovery (`bottrunk_catalog`) and balance checks (`bottrunk_wallet`).

## 2-minute setup

Requires Node 20+.

```sh
# 1. Create the agent's wallet and print its address
npx bottrunk-mcp wallet

# 2. Send it a little USDC on the Algorand network (and ~0.2 ALGO once), then opt in to USDC
npx bottrunk-mcp wallet optin
```

Then add the server to your client.

**Claude Desktop** — `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "bottrunk": { "command": "npx", "args": ["-y", "bottrunk-mcp"] }
  }
}
```

**Claude Code**:

```sh
claude mcp add bottrunk -- npx -y bottrunk-mcp
```

**Cursor** — `.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "bottrunk": { "command": "npx", "args": ["-y", "bottrunk-mcp"] }
  }
}
```

Restart the client. Ask the agent *"what can you buy on BotTrunk?"* and then *"scrape https://example.com/pricing to markdown"* — the first is free, the second costs 0.005 USDC and comes back with the transaction id.

## Tools

| Tool | Cost | What it does |
|---|---|---|
| `bottrunk_catalog` | free | Lists services with price, inputs and status. Optional `query` filter. |
| `bottrunk_wallet` | free | Address, ALGO/USDC balances per network, caps, spent today. |
| `bottrunk_<slug>` | per call | One tool per **live** catalog service, e.g. `bottrunk_scrape_markdown`. Input schema comes from the catalog. |

Services marked `coming_soon` in the catalog are listed but not exposed as tools; the gateway answers 503 for them, so nothing can be charged by accident.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `BOTTRUNK_MNEMONIC` | — | Use an existing 25-word Algorand mnemonic instead of the wallet file. |
| `BOTTRUNK_WALLET_FILE` | `~/.bottrunk/wallet.json` | Where `wallet` writes/reads the generated key. |
| `BOTTRUNK_MAX_PER_CALL` | `1000` | Refuse any single call above this many USDC. |
| `BOTTRUNK_MAX_PER_DAY` | `10000` | Refuse once today's total (UTC) would pass this many USDC. |
| `BOTTRUNK_API` | `https://api.bottrunk.com` | Gateway base URL (catalog + paid endpoints). |
| `ALGORAND_NETWORK` | `mainnet` | Network for `wallet optin` only; paid calls follow whatever the 402 says. |

Pass them through your client's `env` block:

```json
"bottrunk": {
  "command": "npx",
  "args": ["-y", "bottrunk-mcp"],
  "env": { "BOTTRUNK_MAX_PER_CALL": "0.05", "BOTTRUNK_MAX_PER_DAY": "1" }
}
```

## How a paid call works

1. The tool POSTs the arguments to `https://api.bottrunk.com/s/<slug>`.
2. The gateway answers `402` with the price, the `payTo` address and the network (CAIP-2).
3. The server checks the caps, builds an Algorand USDC transfer for exactly that amount, signs it locally, and retries with a `PAYMENT-SIGNATURE` header.
4. The gateway verifies with the facilitator, runs the service, settles on-chain, and answers `200` with a `PAYMENT-RESPONSE` receipt.
5. The tool result is the service output plus one line: `— paid 0.005 USDC · txn <id>`.

If step 3 or 4 fails nothing is charged; if the service fails after settlement the gateway still returns what it has, because the money already moved.

## Security notes

- Treat `~/.bottrunk` like `~/.ssh`. Back the wallet file up; it is the only copy of the key.
- Keep only what you are willing to spend in the agent wallet. Top it up from your main wallet.
- The caps are enforced locally by this process; an agent cannot raise them from inside a tool call.
- The server prints nothing to stdout except MCP frames; all logs go to stderr.

## Development

```sh
npm install
npm test        # builds, then runs the suite against an in-process fake gateway + fake algod
npm run build
node dist/cli.js catalog
```

Part of the [BotTrunk](https://github.com/JorgePadilla/BotTrunk) monorepo (`mcp-hub/`). MIT.
