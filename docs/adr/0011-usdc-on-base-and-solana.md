# ADR 0011 — Take USDC on Base and Solana as well as Algorand

**Status:** accepted · **Date:** 2026-10-18

## Context
Over the 30 days to Oct 18, 2026, our endpoints answered 84,396 unpaid requests with a 402, saw one payment attempt, and had no settled payment from a wallet that was not ours. Industry reports for 2026 put nearly all x402 payments on Solana (about 70% of monthly volume by August) and Base (second, and largest by lifetime count). An agent holding USDC there found no option in our 402 it could pay with, and left without a trace. GoPlausible, our facilitator, already settles the `exact` scheme on Base and Solana (`GET /supported`, checked Oct 18).

## Decision
- The 402 lists one option per network: Algorand first, then Base and Solana once their receiving address is configured (`BASE_PAY_TO`, `SOLANA_PAY_TO`). Same price in µUSDC on every network.
- A payment is verified and settled against the option for the network it was signed for. A network we do not take gets a 402 naming the ones we do.
- The facilitator client is `Payments::Adapters::Facilitator` (formerly `Algorand`, kept as an alias); it was never chain-specific.
- `calls.network` records where each payment settled; refused payments record the network they tried. `/admin/stats` shows both.
- Still no keys on the server: we publish receiving addresses only.

## Consequences
- Off until configured: a deploy without the two addresses serves exactly the old 402.
- Volume on Base and Solana does not count on the Algorand challenge leaderboard.
- Sellers are still paid on Algorand. USDC received on Base or Solana is moved by hand when needed; `/admin/payouts` shows what each network received.
- `bottrunk-mcp` signs Algorand only and keeps choosing the Algorand option (tested with Base and Solana listed first).
