# ADR 0006 — Money as integer atomic units

**Status:** accepted · **Date:** 2026-09-02

## Context
Prices like $0.005 and commission splits must round deterministically and match what the chain records.

## Decision
All persisted amounts are integers in the asset's atomic unit (USDC: µUSDC, 6 decimals), with the asset and network stored alongside. Commission is computed in integers; when a split does not divide evenly, the remainder goes to the seller (the platform absorbs rounding). Floats appear only in display code (`Catalog::PriceComponent`).

## Consequences
- Ledger sums are exact and reconcilable against on-chain transfers.
- A `Money`-like value object may be introduced when a second asset arrives; not before.
