# Distribution: where BotTrunk is listed and how to list it

The directories agent builders browse, in the order worth doing them. Audit of Oct 2, 2026: BotTrunk was on npm (377 downloads/week) and in the GoPlausible Bazaar only; none of the MCP directories had it, while rival Algorand servers (Agent402, Fry.farm) were in most. Every entry below is copy-paste ready. Accounts, pull requests and publishing are done by Jorge.

## The one-liner

Use the same words everywhere, so a search for any of them lands on the same thing:

> Pay-per-call AI services for agents: USDC over x402 on Algorand, paid from your own wallet.

Longer (when a directory allows ~300 characters):

> MCP server whose tools are paid services: scraping, screenshots, PDFs, DNS, email checks, and work done by real people (a bank deposit in Honduras, a business verification). The agent pays each call in USDC over x402 from its own Algorand wallet, with per-call and per-day caps. No account, no API key.

## 1. Official MCP Registry (do first: PulseMCP and others copy from it)

`mcp-hub/server.json` is ready and validated against the 2025-12-11 schema; `package.json` carries the matching `mcpName` (`com.bottrunk/bottrunk`) and version 0.4.1. The registry checks the published npm package for that `mcpName`, so the order matters:

1. `cd mcp-hub && npm publish` (0.4.1).
2. Create the DNS key once. macOS's own `openssl` lacks Ed25519, so use Homebrew's:
   ```bash
   OPENSSL=/opt/homebrew/opt/openssl@3/bin/openssl
   $OPENSSL genpkey -algorithm Ed25519 -out ~/.bottrunk-registry-key.pem
   $OPENSSL pkey -in ~/.bottrunk-registry-key.pem -pubout -outform DER | tail -c 32 | base64   # → PUBLIC_KEY
   ```
   Keep the `.pem` in the password manager; it is what lets you publish later versions.
3. Namecheap → bottrunk.com → Advanced DNS → add a **TXT** record on the apex (`@`): `v=MCPv1; k=ed25519; p=PUBLIC_KEY`. It sits next to the existing SPF record; they don't collide.
4. Install the publisher (`brew install mcp-publisher`) and publish:
   ```bash
   PRIVATE_KEY="$($OPENSSL pkey -in ~/.bottrunk-registry-key.pem -noout -text | grep -A3 "priv:" | tail -n +2 | tr -d ' :\n')"
   mcp-publisher login dns --domain bottrunk.com --private-key "$PRIVATE_KEY"
   mcp-publisher publish          # from mcp-hub/, reads server.json
   ```
5. Check: `curl "https://registry.modelcontextprotocol.io/v0/servers?search=bottrunk"`.

Every later release: bump `version` in both `package.json` and `server.json` (a test fails if they differ), `npm publish`, `mcp-publisher publish`. A version can be published to the registry only once.

## 2. Glama, then the awesome lists

- **Glama** (glama.ai/mcp/servers → Add Server): the GitHub repo URL. Categories: Finance, Cryptocurrency. The punkpeye list expects a Glama score badge, so this goes before step 3.
- **GitHub repo metadata** (Glama and the lists read it): description = the one-liner, homepage `https://bottrunk.com`, topics `mcp mcp-server x402 algorand usdc ai-agents payments`.
- **punkpeye/awesome-mcp-servers**, section "Finance & Fintech", PR adding:
  ```
  - [JorgePadilla/BotTrunk](https://github.com/JorgePadilla/BotTrunk) 📇 ☁️ 🏠 🍎 🪟 🐧 - Pay-per-call services for agents (scraping, screenshots, PDFs, DNS, human-fulfilled jobs) paid in USDC over x402 on Algorand from the agent's own wallet, with spend caps. No API key.
  ```
- **punkpeye/awesome-remote-mcp-servers**, section "Payments": `https://mcp.bottrunk.com/mcp`, Streamable HTTP, no auth, free and read-only (catalog, prices, how to pay).
- **xpaysh/awesome-x402** and **Merit-Systems/awesome-x402**, section "MCP" or "Tools & Services":
  ```
  - [BotTrunk](https://bottrunk.com) - Composite x402 marketplace on Algorand: data utilities and human-fulfilled services, with an MCP server (`npx bottrunk-mcp`) that pays from the agent's own wallet.
  ```

## 3. Directories with a form

- **Smithery** (smithery.ai/new): the remote URL `https://mcp.bottrunk.com/mcp`. A public server with no auth is scanned automatically; if the scan fails, it needs a server card at `/.well-known/mcp/server-card.json`. The npm (stdio) server would need an MCPB bundle instead; skip it.
- **mcp.so**, **cursor.directory**: the submit forms, with the one-liner and the npm install line `npx -y bottrunk-mcp`.
- **mcpservers.org**: the free form (two-week review).

## Not yet

- **x402.org ecosystem**: the page is offline and the list in coinbase/x402 has 100+ unmerged PRs.
- **x402scan**: lists only facilitators and chains it supports, and Algorand isn't one; another chain is Phase 2.
- **Bazaar listings for the 14 services never paid for**: a service is listed after its first real settle. Only real buyers can do that; never self-call.
