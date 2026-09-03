# ADR 0004 — x402 on Algorand via the GoPlausible facilitator, behind an adapter

**Status:** accepted · **Date:** 2026-09-02

## Context
Agents need a payment rail that works without accounts or cards. x402 is HTTP-native and now has multi-chain facilitators. The Global x402 Challenge (Algorand Foundation) rewards real MainNet usage on Algorand through the GoPlausible facilitator, and its Composite entry type matches a gateway with many endpoints.

## Decision
- Implement x402 v2, scheme `exact`, USDC ASA on Algorand (TestNet first, then MainNet).
- Verification and settlement are delegated to `https://facilitator.goplausible.xyz` (`/verify`, `/settle`). The gateway never signs transactions and holds no private keys; it only builds payment requirements and calls the facilitator.
- The chain-specific code lives in `Payments::Adapters::Algorand` behind `Payments::Adapters::Base`. Everything else in the app speaks `Payments::Requirements` / `Payments::Payload` / `Payments::Receipt`.
- The paywall is Rack middleware in front of `POST /s/:slug/*path`.

## Consequences
- Adding Base/Coinbase or Solana later is a new adapter plus a `network` column, not a rewrite.
- We depend on a third-party facilitator's uptime; mitigations: timeouts, retries on reads, and the async settle job.
- Non-custodial by construction, which keeps the regulatory surface small until credits (Phase 2) are considered.
