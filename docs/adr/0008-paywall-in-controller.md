# ADR 0008 — The x402 paywall is a controller + orchestrating service, not Rack middleware

**Status:** accepted · **Date:** 2026-09-10

## Context
The plan placed the paywall in `app/middleware/x402_paywall.rb` (Rack). Writing the Phase 0 spike showed the middleware bought nothing: the paid endpoint needs the route's `:slug`, the raw body and the ability to render JSON — all things a controller already has — and middleware under `app/` needs Zeitwerk workarounds (`autoload_once_paths`) to be referenced from the middleware stack.

## Decision
`POST /s/:slug` → `PaidCallsController#create` → `Gateway::HandlePaidCall`, one service that runs the fixed order **402 → verify → upstream → settle → record** by composing `Payments::BuildRequirements`, `Payments::VerifyPayment`, `Gateway::ProxyCall`, `Payments::SettlePayment` and `Ledger::RecordTransaction`. The controller only moves bytes: header in, status/body/`X-PAYMENT-RESPONSE` out.

## Consequences
- Integration tests exercise the whole loop with `post paid_call_path(...)`; no Rack env plumbing.
- `Gateway::HandlePaidCall` is the only place that knows the order of the loop; everything under it stays independently unit-testable.
- `app/middleware/` does not exist. If a Rack-level concern appears later (rate-limiting unpaid probes), `rack-attack` covers it.
