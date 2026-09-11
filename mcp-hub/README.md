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

# 2. Fund it. Two sends to that address, in this order:
#      0.3 ALGO   (0.1 for the account to exist, 0.1 to hold USDC, the rest for fees)
#      the USDC you want this agent to be able to spend
#    The USDC opt-in in between happens by itself on the first paid call.
```

An agent cannot fund itself: an Algorand account needs ALGO before it can hold
anything, and only the key holder can sign an ASA opt-in. USDC sent before the
opt-in is **rejected, not held**, which is why the order matters.

**Already run an Algorand account?** Skip all of it — put its 25 words in
`BOTTRUNK_MNEMONIC` and the agent uses that account directly.

**One approval instead of two sends:**

```sh
npx bottrunk-mcp wallet fund --from <your address> --usdc 5
```

Builds a single atomic group — fund, opt in, deliver USDC — signs the agent's
opt-in, and checks the whole thing against real chain state with algod's
`simulate` before anyone is asked to approve it. Nothing is submitted and
nothing is spent by that check. You sign transactions 0 and 2 with your own
wallet and submit all three together; all three land or none do, so the
ordering trap cannot happen. The group expires in about 45 minutes.

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

**Cursor** — `~/.cursor/mcp.json` (or `.cursor/mcp.json` per project):

```json
{
  "mcpServers": {
    "bottrunk": { "command": "npx", "args": ["-y", "bottrunk-mcp"] }
  }
}
```

Restart the client. Ask the agent *"what can you buy on BotTrunk?"* and then *"scrape https://example.com/pricing to markdown"* — the first is free, the second costs 0.09 USDC and comes back with the transaction id.

## Other clients

Same server everywhere; only the spelling changes. Full steps with links to each client's own docs: https://bottrunk.com/connect

| Client | Where it goes |
|---|---|
| Claude Code | `claude mcp add bottrunk -- npx -y bottrunk-mcp` |
| Claude Desktop | `claude_desktop_config.json` → `mcpServers` |
| Cursor | `~/.cursor/mcp.json` → `mcpServers` |
| VS Code (Copilot) | `.vscode/mcp.json` → **`servers`**, with `"type": "stdio"` |
| Cline | `~/.cline/mcp.json` → `mcpServers` |
| Windsurf | `~/.codeium/windsurf/mcp_config.json` → `mcpServers` |
| Zed | `settings.json` → **`context_servers`** |
| OpenClaw | `openclaw mcp add bottrunk --command npx --arg -y --arg bottrunk-mcp` |
| Hermes Agent | `~/.hermes/config.yaml` → `mcp_servers` |
| Goose | `goose configure` → Command-Line Extension → `npx -y bottrunk-mcp` |
| OpenAI Agents SDK | `MCPServerStdio(params={"command": "npx", "args": ["-y", "bottrunk-mcp"]})` |
| LangChain / LangGraph | `MultiServerMCPClient({"bottrunk": {...,"transport": "stdio"}})` |

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
| `ALGORAND_NETWORK` | `mainnet` | Network for `wallet optin` and `wallet fund`; paid calls follow whatever the 402 says. |
| `BOTTRUNK_OPERATOR` | — | Default `--from` address for `wallet fund`. |

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
5. The tool result is the service output plus one line: `— paid 0.09 USDC · txn <id>`.

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
