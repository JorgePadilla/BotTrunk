---
paths:
  - "gateway/app/services/payments/**"
  - "gateway/app/middleware/**"
---
# Payments and the x402 paywall

- Protocol facts (endpoints, network ids, USDC ASA ids, header shapes) live in `docs/x402-algorand.md`. Update that file when reality differs; never hardcode a value that isn't there.
- Chain/facilitator specifics stay inside `Payments::Adapters::*` behind `Payments::Adapters::Base`. Everything else speaks `Payments::Requirements`, `Payments::Payload`, `Payments::Receipt`.
- Order of operations is fixed: 402 → verify → fulfil upstream → settle → record. Never settle before a successful upstream response; never spend upstream compute before verify.
- Amounts: integer atomic units, asset + network stored alongside. Commission remainder goes to the seller.
- The gateway never signs transactions or holds private keys. If code needs a key, the design is wrong.
- Every facilitator call has a timeout; retries only on idempotent reads.
