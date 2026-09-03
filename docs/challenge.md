# Global x402 Challenge — what we know

Sources: Algorand Foundation registration email (Sept 3, 2026 — Jorge is registered) and the official "how to build & submit" post: https://algorand.co/blog/the-x402-global-challenge-is-live-how-to-build-submit-your-entry. Official rules PDF: https://algorand.co/hubfs/x402%20competition%20Official%20Rules.pdf — still to be read for eligibility wording.

## Timeline

| When | What |
|---|---|
| Now | Build phase is live. Ship a paid x402 endpoint on Algorand MainNet and drive real usage. |
| Until late September | **Submission window.** The form is emailed by the Foundation ("keep an eye on your inbox"). Exact date TBA. |
| September → early October | Leaderboard period: usage is measured continuously. Keep driving real calls. |
| Through October | Leaderboard closes; top 50 by usage *that also submitted* are reviewed. |
| Mid-October | 10 finalists announced. |
| Early November | Finalists present live at Devcon 8 India (remote allowed per earlier research — confirm in rules). |

Dates are "to be announced" per the email — check the inbox weekly and update this table.

## Entry types

- **Standard** — one paid endpoint, one service.
- **Composite** — multiple endpoints under one project sharing the same `payTo` address. ← **BotTrunk enters here** (seed catalog, one gateway wallet).
- **Orchestrator** — a service that coordinates and pays other x402 endpoints in its workflow. ← Phase 3 (agent budget routing).

## Qualification checklist (from the email)

- [ ] Build and test the x402 endpoint on TestNet.
- [ ] Deploy to MainNet with a public HTTPS endpoint (`api.bottrunk.com`).
- [ ] Use the GoPlausible facilitator and enable Bazaar discovery.
- [ ] Add the required `x402-global-challenge` tag.
- [ ] Complete at least one real MainNet payment and confirm USDC is received.
- [ ] Confirm the endpoint appears in the Bazaar and on the leaderboard.
- [ ] Keep driving real usage through early October.
- [ ] Submit the project via the Foundation's form before the late-September deadline.

## Mechanics (from the build & submit post)

- **payTo:** one Algorand address for the whole competition, opted in to USDC (ASA `31566704`). Leaderboard volume is attributed to it. **Never reuse a payTo across different domains** (regulatory rule) — one wallet for `api.bottrunk.com`, period.
- **Tag:** put `"tag": "x402-global-challenge"` inside the `extra` object of the 402 payment requirements.
- **Bazaar discovery:** the 402 response carries an `extensions.bazaar` object (`info.input` = method/params/type, `info.output` = example + schema, plus a `schema`); the client copies `extensions` into the payment payload and the facilitator catalogs the resource **on settle**. No registration call. The route `description` is what shows in the catalog — concrete, say what the caller gets.
- **Metadata the Bazaar enriches from:** site OpenGraph (title, description, logo), `llms.txt` / agentic files, well-known structures on the domain, and the merchant's NFD (Algorand name). Optional: register an NFD for BotTrunk.
- **Leaderboard:** real MainNet USDC settled through GoPlausible; Composite entries are summed across endpoints sharing the payTo. View at https://facilitator.goplausible.xyz/dashboard/leaderboards (global-hackathon filter on). Catalogs: https://facilitator.goplausible.xyz/discovery/resources and `/discovery/merchants`. TestNet activity does not count; the entry appears only after the first real MainNet settlement.
- **Reference code:** official demo server https://github.com/algorandfoundation/x402-demo/tree/main/x402-basic-tutorial · developer guide https://algorand.co/agentic-commerce/x402/developers · example https://dev.algorand.co/resources/x402-on-algorand/ · agent skills https://github.com/algorand-devrel/algorand-agent-skills · npm `@x402-avm/extensions` (Bazaar) and the Algorand x402 packages · Discord https://discord.com/invite/algorand.
- Submission form: details "closer to the deadline" (late September). Watch the inbox.

## How entries are judged

Gate: be in the **top 50 by usage** on the leaderboard and have submitted. Then reviewed on:

1. **Volume** — total USDC processed; how real and measurable the activity is.
2. **Use-case quality** — x402 is core to the payment flow, not bolted on; clear value in pay-per-request, agentic payments, API monetization, data access or digital services.
3. **Technical execution** — reliable endpoint, correct settlement.
4. **Sustained potential** — a credible path to usage after the prize period.
5. **Innovation** — a novel or technically meaningful use of x402.

What this means for BotTrunk: volume is the gate, so the seed data utilities (cheap, instant, agent-friendly) must be live on MainNet early and promoted hard; the MCP hub is the volume engine. "Not bolted on" is our strongest card — the marketplace *is* the payment flow. Sustained potential = the commission model and outside sellers.

## Prizes (100K USDC + 500K ALGO, terms apply)

| Place | USDC |
|---|---|
| 1st | $25,000 |
| 2nd | $22,500 |
| 3rd | $20,000 |
| 4th | $17,500 |
| 5th | $15,000 |
| Top 20 leaderboard | 500,000 ALGO split across the top 20 endpoints |

## Resources named in the email

- x402 on Algorand Developer Portal
- x402 + Agentic Commerce overview
- Algorand x402 official npm package (the client for `mcp-hub` and the Phase 0 spike script)
- GoPlausible facilitator docs — https://facilitator.goplausible.xyz/docs
- VibeKit (Algorand skills for AI coding tools)
- Discord for Dev Rel / engineering support

(Email links are tracking URLs; paste the real ones here when opened.)

## Project description used on the registration form (Sept 3)

> BotTrunk is a pay-per-call marketplace for AI agents. Developers register any HTTP API with a price; BotTrunk hosts it behind an x402 paywall on Algorand, so agents pay USDC per request with no accounts, API keys or subscriptions, and sellers get settled instantly — including developers in Latin America that card-based platforms leave out. Every endpoint returns HTTP 402 with payment requirements, verifies and settles through the GoPlausible facilitator, proxies the call upstream, and records a commission ledger. An MCP hub exposes the whole catalog as payable tools for Claude, GPT and LangChain agents. We're launching with self-hosted data utilities (scrape-to-markdown, PDF extraction, screenshots) as a Composite entry, with human-fulfilled services (business verification in Honduras, local-context translation) next — the gateway doesn't care whether the fulfiller behind an endpoint is code or a person.
