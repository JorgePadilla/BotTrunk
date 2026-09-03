# BotTrunk

Pay-per-call marketplace for AI agents over x402 (HTTP 402 + USDC on Algorand via the GoPlausible facilitator; the payment layer is an adapter so other chains can follow). We take 10–15% per transaction.

Monorepo: `gateway/` (Rails 8.1 — registry, x402 paywall + proxy, catalog, ledger) · `mcp-hub/` (TypeScript MCP server, Phase 1, not started).

## Read next

| Need | File |
|---|---|
| What to do now | `docs/phase-0.md` |
| Hackathon dates, checklist, judging | `docs/challenge.md` |
| How the code is organized | `docs/architecture.md` |
| Why each gem/lib | `docs/stack.md`, `docs/adr/` |
| x402 / Algorand / facilitator facts | `docs/x402-algorand.md` |
| Rails conventions (auto-loaded inside `gateway/`) | `gateway/CLAUDE.md`, `.claude/rules/` |
| Product plan and phases | Claude project doc `claude/plan.md` |

## Non-negotiables

- English for code, comments, commits, docs. Commits: imperative subject ≤ 72 chars, body says *why*.
- Money is stored as integer atomic units (µUSDC). Never floats in the ledger.
- Only `gateway/app/services/payments/` knows about chains, facilitators or payment headers.
- No secrets in the repo; the server never holds wallet keys — it only receives.
- Every change ships with a test. Every reusable UI piece is a ViewComponent with a Lookbook preview.

## Current phase

Phase 0 (Sept 2026): prove one paid x402 call on Algorand TestNet end to end. Checklist in `docs/phase-0.md`. Don't start Phase 1 features without asking.
