# Product plan and phases

The working roadmap. It used to live only as a Claude.ai project doc (`claude/plan.md`), which isn't in the repo and so drifted out of sight; this file replaces it and is rebuilt from what the repo records (phase-0.md, challenge.md, architecture.md, stack.md, the ADRs, git history). Update it when a phase moves.

## Where we are (Sept 29, 2026)

- **Phase 0 — done** (Sept 10). One paid x402 call on TestNet end to end; go/no-go was GO. Details in [phase-0.md](phase-0.md).
- **Phase 1 — in progress.** MainNet, the MCP hub and a real catalog are live; seller self-service is not.
- **Challenge:** final submission sent before the Sep 29 deadline. Next dates: shortlist **Oct 9**, final presentation **Nov 2** (virtual). Leaderboard volume keeps counting until the review. See [challenge.md](challenge.md).

## Phase 1 — Live marketplace (Sept → Oct 2026)

Goal: a public MainNet marketplace that other people's agents actually use, and a path for outside sellers.

Done:

- [x] MainNet at `api.bottrunk.com` on Render, TLS, GoPlausible `/verify` + `/settle`, Bazaar discovery, `x402-global-challenge` tag, listed on the leaderboard (Sept 11).
- [x] `bottrunk-mcp` on npm (v0.4.0): one tool per live service, pays from the agent's own wallet, spend caps (`BOTTRUNK_MAX_PER_CALL`). Hosted read-only MCP at `mcp.bottrunk.com/mcp`.
- [x] Catalog of built-in services (scrape, screenshot, PDF, metadata, links, URL health, DNS, email check) and human-fulfilled ones (HN deposits, RFQ, business verification, translation, human review, local prices) with work orders and an admin queue.
- [x] `/connect` page for every major agent runtime; `/docs`, `/sell`, JSON catalog API (ADR 0007), `llms.txt`, OpenGraph.
- [x] Admin stats dashboard, seller inquiries, daily digest email (Resend + Render cron).
- [x] CI on GitHub Actions: gateway tests, RuboCop, Brakeman, mcp-hub build + tests (Sept 29).

Open:

- [ ] **Distribution — real usage from other people's agents.** The gate for the challenge and the point of the product. Never script self-calls.
- [ ] **Seller sign-up and auth**: turns `SellerInquiry` into accounts; `Catalog::Service` moves from in-code seed to an ActiveRecord model (see `architecture.md` §3).
- [ ] **Seller dashboard**: `stat_row`, `calls_table`, `endpoint_form`, `api_key_reveal` components (`architecture.md`).
- [ ] **"Pay with wallet" for humans**: a wallet-connect button, since phone-wallet 24-word HD phrases can't be used by the SDKs.
- [ ] **Hardening before real traffic** (`deploy.md`, `stack.md`):
  - [x] Rate limits with `rack-attack` on `/s/*`, `/mcp` and the public forms (Oct 1).
  - [ ] Error tracking (Sentry or Honeybadger).
  - [ ] Solid Queue + `SettlePaymentJob`, if settlement goes async.
- [ ] **GitHub org move** once Support releases `bottrunk` (by Dec 2 at the latest): create the org, transfer the repo, reinstall the Claude GitHub App, update the remote.

## Phase 2 — Sellers and non-crypto buyers

- Payouts to outside sellers (85 % share already in the ledger).
- Earnings chart in the seller dashboard (library decided then — likely inline SVG in a component, `stack.md`).
- Non-crypto path: card-bought credits (`Agent ──< ApiKey, Credit`, `architecture.md`). This changes the regulatory surface; ADR 0004 keeps us non-custodial until then — decide deliberately.

## Phase 3 — Orchestration

- Agent budget routing: a service that coordinates and pays other x402 endpoints on an agent's behalf (the challenge's "Orchestrator" entry type).

## Rules that hold across phases

The non-negotiables in the root `CLAUDE.md`: integer µUSDC, only `app/services/payments/` knows about chains, no keys on the server, every change ships with a test.
