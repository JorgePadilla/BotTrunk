# ADR 0010 — One free call per caller, opt-in, with nothing settled

**Status:** accepted · **Date:** 2026-10-17

## Context
The first thing a new agent meets is "fund a wallet on Algorand": buy ALGO and USDC, opt in, send both. Most never get past it, so they never see what a call returns. Outside usage, the Phase 1 milestone, was close to zero on Oct 17. Two ways to lower the barrier were weighed: a free first call, and seeding new wallets with a little USDC from a wallet of ours. Seeding needs a signing key outside the server, invites throwaway wallets to drain it, and pays for calls with our own money, which then looks like self-payment volume. It was turned down.

## Decision
- **Opt-in.** A request without payment still gets the ordinary 402, so x402 clients and Bazaar probes see nothing new. For an eligible service the 402 adds `trial` to its body and a `BotTrunk-Trial: available` header. Repeating the request with `X-BotTrunk-Trial: 1` runs the service for free; the answer carries `BotTrunk-Trial: used` and a `BotTrunk-Fund` link.
- **Cheap built-ins only** (`Gateway::GrantTrial::SERVICES`): the judgment services and the plain-fetch data services. Nothing rendered by a paid browser, nothing a person fulfils, nothing that moves money.
- **One per caller every 30 days, at most 100 a day in total.** The caller is a secret-salted fingerprint of the IP, stored on trial events only, because the daily-rotating `visitor` token cannot count 30 days. Only a 200 uses the trial.
- **Never a Call.** A trial is an `Event` named `trial_call`. No payment is verified or settled, so volume, the ledger and outside usage stay real money.
- **A request that carries a payment is a paid call**, trial header or not.

## Consequences
- This is the one deliberate exception to "never spend upstream compute before verify" (`.claude/rules/payments.md`). The daily cap bounds what it can cost: at most 100 cheap calls a day, fractions of a cent each.
- IP-keyed limits leak (shared IPs, proxies). The cap is what makes that acceptable.
- `/admin/stats` shows free trials apart from paid usage.
- `bottrunk-mcp` can use the trial when its wallet cannot pay (next release).
