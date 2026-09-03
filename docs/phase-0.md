# Phase 0 — Spike & register

**Window:** September 2026, weeks 1–2 · **Budget:** ~10–15 focused hours · **Owner:** Jorge

## Goal

Prove, end to end and on Algorand TestNet, that a Rails app can sell one paid API call over x402: an agent hits an endpoint, gets a 402, pays USDC, the facilitator verifies and settles, the gateway proxies the call upstream and returns the result. If this works in two weeks, the five-week window for the Global x402 Challenge is realistic; if not, we know early and cut scope.

Phase 0 produces no product features. It produces certainty, three registered names, and a working loop with tests.

## Checklist

### A. Identity and accounts

- [x] Register `bottrunk.com` — done Sept 3, 2026 (Namecheap, 5 years). Point nothing yet.
- [x] Repo created: `github.com/JorgePadilla/BotTrunk` (Sept 3, public).
- [ ] Push the monorepo (`git init -b main && git add -A && git commit && git push -u origin main`).
- [ ] Ask GitHub Support to release the `bottrunk` org name (created + deleted Sept 3, now on hold; GitHub's usual hold is ~90 days → **Dec 2, 2026** at the latest, likely sooner via support). When released: create the org, transfer the repo (Settings → Transfer), install the Claude GitHub App on the org with "All repositories", `git remote set-url origin git@github.com:bottrunk/bottrunk.git`.
- [ ] Read the challenge's official rules PDF and the submission guide linked from the registration email; record exact dates and the guide URL in `docs/challenge.md`.
- [ ] Create an Algorand wallet for the gateway (Pera or Defly). Store the mnemonic in a password manager; never in the repo. Record the address as the Phase 0 `payTo`.
- [ ] Fund it on TestNet: ALGO from the TestNet dispenser, then opt in to TestNet USDC (ASA `10458941`) and get test USDC from the faucet.
- [ ] Create a second wallet to act as the *paying agent* in the spike.

### B. Repo hygiene (½ hour)

- [ ] `cd gateway && bundle install && bin/rails rails_icons:install --libraries=lucide && bin/setup && bin/rails test` — all green.
- [ ] `git init`, first commit, push to the org. Enable the CI workflow (`.github/workflows/ci.yml`).
- [ ] Add `faraday`, `faraday-retry`, `webmock` (test) to the Gemfile.

### C. The x402 spike (the real work, ~8 hours)

Build it as real code in its final place, not a throwaway script — the spike *is* the first slice of Phase 1.

1. **Payment requirements.** `Payments::BuildRequirements.call(service:)` → the JSON body of the 402 (see `docs/x402-algorand.md` for exact field names). Unit test the shape.
2. **Middleware.** `X402Paywall` in `app/middleware/`, mounted for `POST /s/:slug/*path`. No `X-PAYMENT` header → 402 with requirements. With header → decode, hand to the verify service.
3. **Verify.** `Payments::VerifyPayment.call(payment_header:, requirements:)` → `Payments::Adapters::Algorand#verify` → `POST https://facilitator.goplausible.xyz/verify`. WebMock the facilitator in tests; hit the real one manually on TestNet.
4. **Proxy.** `Gateway::ProxyCall.call(service:, request:)` → Faraday to a fixed upstream (use `https://httpbin.org/anything` or a tiny internal Rack app first), timed, response captured.
5. **Settle.** `Payments::SettlePayment.call(...)` → `/settle`. Synchronous in the spike; the async path (Solid Queue job) is a Phase 1 task.
6. **Ledger.** `Ledger::RecordTransaction` writes one `Call` row: service, payer, amount (µUSDC integer), commission, upstream latency, facilitator tx id.
7. **Client.** A small script under `gateway/script/x402_client.rb` (or the official TypeScript client in `mcp-hub/`) that pays from the agent wallet. First real TestNet transaction = spike done.

### D. Definition of done

- One paid call completes on TestNet: 402 → pay → verify → proxy → settle → 200, with the Algorand tx id visible in the `calls` table.
- `bin/rails test` covers the loop with a fake adapter (no network) and stays green.
- `docs/x402-algorand.md` has every value we had to look up during the spike (including anything that turned out different from what's written today).
- Domain, org and wallets exist; `payTo` recorded.
- A go/no-go note at the bottom of this file: does the 5-week Phase 1 look realistic?

## Challenge facts

Registered Sept 3, 2026. Everything known (timeline, entry types, checklist, judging, prizes) lives in `docs/challenge.md` — keep that file current as the Foundation announces dates. Short version: submit by **late September** (form arrives by email), stay in the **top 50 by usage** through October, 10 finalists mid-October, Devcon 8 India early November. We enter as **Composite**.

## Out of scope for Phase 0

Seller sign-up, dashboards, MCP hub, credits/card payments, human-fulfilled services, production deploy. All Phase 1+.

## Go / no-go

_(write the answer here at the end of week 2)_
