# Phase 0 — Spike & register

**Window:** September 2026, weeks 1–2 · **Budget:** ~10–15 focused hours · **Owner:** Jorge

## Goal

Prove, end to end and on Algorand TestNet, that a Rails app can sell one paid API call over x402: an agent hits an endpoint, gets a 402, pays USDC, the facilitator verifies and settles, the gateway proxies the call upstream and returns the result. If this works in two weeks, the five-week window for the Global x402 Challenge is realistic; if not, we know early and cut scope.

Phase 0 produces no product features. It produces certainty, three registered names, and a working loop with tests.

## Checklist

### A. Identity and accounts

- [x] Register `bottrunk.com` — done Sept 3, 2026 (Namecheap, 5 years). Point nothing yet.
- [x] Repo created: `github.com/JorgePadilla/BotTrunk` (Sept 3, public).
- [x] Repo pushed and in sync with `origin/main` (Sept 10: UI fixes, wallets, credentials, x402 loop + tests).
- [x] GitHub Support ticket filed Sept 3 asking to release the `bottrunk` org name (GitHub confirms deleted org names are locked for **90 days → Dec 2, 2026**; Support may release it sooner). Watch the inbox / support.github.com → My Tickets. When released: create the org, transfer the repo (Settings → Transfer), install the Claude GitHub App on the org with "All repositories", `git remote set-url origin git@github.com:bottrunk/bottrunk.git`.
- [x] Rules PDF and submission guide read (Sept 3); exact dates recorded in `docs/challenge.md`: **submit by Sep 29, 11:45 pm ET**, shortlist Oct 9, final Nov 2, winners by Nov 12. Self-payments don't count as volume.
- [x] Create an Algorand wallet for the gateway (Defly, Sept 9). Mnemonic in the password manager; never in the repo. `payTo` = `UTWS33TM7IT7NINJSFWS5KVGL73G4ERJMYDKHF7KE4WDXHYO4L7V2PNMRE` — recorded in `docs/x402-algorand.md` and in Rails encrypted credentials as `algorand.pay_to` (`credentials.yml.enc` committed, `master.key` git-ignored, copy in the password manager).
- [x] Fund it on TestNet: 10 ALGO from https://bank.testnet.algorand.network, opted in to USDC `10458941`, 7.5 USDC from https://faucet.circle.com (Sept 10). Lessons: the faucet has a ~2 h per-address cooldown and a transfer to a non-opted-in account bounces silently.
- [x] Second wallet in Defly (`ABEAGNREVBDSINTSOWXYXOANZDRTLBWDGULA3SALTWRMXNEED2LWZNSADE`, 5 USDC from Circle) acts as the *bank*; the actual spike payer is a 25-word account generated on the Mac by `bin/agent-wallet` (`LQAWG3WUMKWTFGEFCCOET6JGPRKD2JFYPIJ6HPIRYAC6QDUJSBDVMCKPFQ`, mnemonic only in `gateway/.env.local`) because Defly HD wallets export 24-word BIP39 phrases the Python SDK can't derive.

### B. Repo hygiene (½ hour)

- [x] `bundle install`, `rails_icons:install --library=lucide`, `bin/dev` — app boots (Sept 3; runs on port 5000 locally because 3000 is taken by another project). Catalog, service page, theme toggle and Lookbook verified in the browser.
- [x] `bin/rails db:prepare && bin/rails test` — 33 tests, 0 failures on the first run (Sept 10). Schema dumped and committed.
- [ ] Enable the CI workflow (`.github/workflows/ci.yml`). (Org move waits for GitHub Support.)
- [x] Add `faraday`, `faraday-retry`, `webmock` (test) to the Gemfile (Sept 10 — run `bundle`).

### C. The x402 spike (the real work, ~8 hours)

Build it as real code in its final place, not a throwaway script — the spike *is* the first slice of Phase 1.

1. [x] **Payment requirements.** `Payments::BuildRequirements` → `Payments::Requirements` + `body_for` (402 body with `extra.tag` and `extensions.bazaar`). Tested.
2. [x] **Paywall.** `POST /s/:slug` → `PaidCallsController` → `Gateway::HandlePaidCall` (controller + service instead of Rack middleware — ADR 0008). No `X-PAYMENT` → 402; with header → `Payments::Payload.from_header` → verify.
3. [x] **Verify.** `Payments::VerifyPayment` → `Payments::Adapters::Algorand#verify` → `POST /verify` (Faraday, timeouts, WebMock in tests). Real facilitator not hit yet.
4. [x] **Proxy.** `Gateway::ProxyCall` → Faraday to `Catalog::Service#upstream_url` (every seed service points at `https://httpbin.org/anything` for now), timed.
5. [x] **Settle.** `Payments::SettlePayment` → `/settle`, synchronous; `Payments::Receipt#to_header` becomes `X-PAYMENT-RESPONSE`.
6. [x] **Ledger.** `Ledger::RecordTransaction` writes one `Call` row (migration `create_calls`): amount, 15 % commission and seller share as integers, payer, tx id, upstream status/latency.
7. [x] **Client.** `gateway/script/x402_client.py` (py-algorand-sdk) pays from the agent wallet: 402 → sign USDC transfer → retry with `X-PAYMENT`. First run Sept 10: full loop executed, facilitator parsed and simulated our payment (rejected only for an unfunded payer — see `docs/x402-algorand.md`). Payer is a machine-generated 25-word account (`bin/agent-wallet`, `LQAWG…KPFQ`) because Defly's HD wallets use 24-word BIP39 phrases the Python SDK can't derive. **Spike done Sept 10, 04:10 local:** first settled x402 payment on TestNet — txn `OFJA5EVTED5L3AE4WVUD7UQ44SPN7XKWURSEKIH25LBBF6BIYUEQ`, 5 000 µUSDC from `LQAWG…KPFQ` to `UTWS…MRE`, commission 750 / seller 4 250, upstream 200 in 258 ms, whole request 4.6 s, `calls` row id 1. No adapter changes were needed.

### C′. Pages that were 404 (done Sept 10, while the faucet cooled down)

- [x] `/docs` — how a paid call works, connect snippets (MCP / Python / TypeScript / curl), the **live 402 body** of `scrape-markdown`, header shapes, networks table, catalog API.
- [x] `/sell` — how selling works, pricing (85 % to the seller), early-access form → `SellerInquiry` (`price_atomic` in µUSDC) via `Sellers::CreateInquiry`.
- [x] `/sign_in` — agents don't sign in; two cards (docs / sell). Real seller auth is Phase 1.
- [x] `GET /api/v1/catalog[/:slug]` — JSON catalog for `mcp-hub` (ADR 0007 contract starts here).
- [x] Catalog search (`?q=`, ⌘K), service-page tabs as anchors, pay CTA → docs, footer links, `<meta description>` + OpenGraph on every page, `public/llms.txt` (the Bazaar enriches listings from OG tags and llms.txt), BotTrunk-styled 400/404/422/500 pages.
- [x] `bin/rails db:migrate` + `bin/rails test` — 52 tests green (Sept 10); /docs and /sell checked in the browser.

### D. Definition of done

- One paid call completes on TestNet: 402 → pay → verify → proxy → settle → 200, with the Algorand tx id visible in the `calls` table.
- `bin/rails test` covers the loop with a fake adapter (no network) and stays green.
- `docs/x402-algorand.md` has every value we had to look up during the spike (including anything that turned out different from what's written today).
- Domain, org and wallets exist; `payTo` recorded.
- A go/no-go note at the bottom of this file: does the 5-week Phase 1 look realistic?

## Challenge facts

Registered Sept 3, 2026. Everything known (timeline, entry types, checklist, judging, prizes) lives in `docs/challenge.md` — keep that file current as the Foundation announces dates. Short version: submit by **Sep 29, 2026, 11:45 pm ET** (form arrives by email), stay in the **top 50 by real usage** (self-payments are excluded), shortlist notified **Oct 9**, final presentation **Nov 2 (virtual)**, winners by Nov 12. We enter as **Composite**.

## Out of scope for Phase 0

Seller sign-up, dashboards, MCP hub, credits/card payments, human-fulfilled services, production deploy. All Phase 1+.

## Go / no-go

**GO (Sept 10, 2026 — end of week 1, not 2).** The loop works end to end on TestNet against the real facilitator with no adapter changes; tests are green (52); the site has catalog, docs, sell and a JSON API. The 5-week Phase 1 window (MainNet at `api.bottrunk.com`, first real payment, Bazaar/leaderboard presence, submission by Sep 29) looks realistic. Biggest risks are not technical: real usage from *other* agents for the leaderboard, and time.

Facts learned that Phase 1 must respect: payer accounts need ALGO for fees/min-balance and a USDC opt-in before anything works; the facilitator simulates on `/verify`, so a bad payment costs nothing; a single plain `AssetTransferTxn` with no fee payer is accepted; wallet-app HD phrases (24 words) are not usable by the SDKs — agents will use SDK-generated keys, humans will need a wallet-connect button.
