# x402 on Algorand — facts we build against

Everything here was read from the GoPlausible facilitator docs and the Algorand Foundation guides on 2026-09-02. **Re-verify each value during the Phase 0 spike** and update this file; the facilitator's `/supported` and `/docs` endpoints are the source of truth.

## The loop

1. Client requests a paid resource without payment.
2. Server answers **402** with a JSON body describing acceptable payments.
3. Client builds and signs the payment, base64-encodes it, retries with the **`X-PAYMENT`** header.
4. Server sends the payload to the facilitator's **`/verify`**; if valid, serves the resource.
5. Server sends the payload to **`/settle`**; the facilitator submits it on-chain.
6. Server returns the resource with **`X-PAYMENT-RESPONSE`** (base64 JSON with the settlement result).

Best-practice order from the Algorand guide: respond 402 → verify → fulfil → settle. Never re-implement on-chain verification alongside the facilitator.

## Facilitator (GoPlausible)

| Item | Value |
|---|---|
| Base URL | `https://facilitator.goplausible.xyz` |
| Verify | `POST /verify` |
| Settle | `POST /settle` |
| Supported networks/assets | `GET /supported` |
| OpenAPI | `/docs` |

## Networks and assets

| Network | CAIP-2 identifier (preferred) | Legacy id | USDC ASA | Decimals |
|---|---|---|---|---|
| Algorand MainNet | `algorand:wGHE2Pwdvd7S12BL5FaOP20EGYesN73ktiC1qzkkit8=` | `algorand-mainnet` | `31566704` | 6 |
| Algorand TestNet | `algorand:SGO1GKSzyE7IEPItTxCByw9x8FmnrCDexi9/cOUJOiI=` | `algorand-testnet` | `10458941` | 6 |

Public algod nodes (no token): `https://testnet-api.algonode.cloud`, `https://mainnet-api.algonode.cloud`.

Amounts are strings in **atomic units**: `$0.005` USDC = `"5000"`.

## 402 body — payment requirements

```json
{
  "x402Version": 2,
  "error": "Payment required",
  "accepts": [
    {
      "scheme": "exact",
      "network": "algorand:SGO1GKSzyE7IEPItTxCByw9x8FmnrCDexi9/cOUJOiI=",
      "asset": "10458941",
      "amount": "5000",
      "payTo": "<58-char Algorand address of the gateway>",
      "maxTimeoutSeconds": 60,
      "resource": "https://api.taskfare.ai/s/scrape-markdown",
      "description": "Scrape URL to Markdown",
      "mimeType": "application/json",
      "extra": { "decimals": 6 }
    }
  ]
}
```

Field names confirmed from the facilitator docs: `scheme`, `network`, `asset`, `amount`, `payTo`, `maxTimeoutSeconds`, `extra` (`feePayer?`, `decimals?`). `resource`, `description`, `mimeType` come from the x402 v2 spec; confirm the facilitator echoes them. (`maxAmountRequired` was the v1 name — we do not use it.)

## `X-PAYMENT` header (base64 of this JSON)

```json
{
  "x402Version": 2,
  "scheme": "exact",
  "network": "algorand:SGO1GKSzyE7IEPItTxCByw9x8FmnrCDexi9/cOUJOiI=",
  "payload": {
    "paymentGroup": ["<base64 msgpack txn>", "..."],
    "paymentIndex": 1
  }
}
```

`paymentGroup` is the signed Algorand transaction group; `paymentIndex` is the zero-based position of the USDC transfer inside it (fee-payer / opt-in txns may precede it).

## `/verify` and `/settle`

Request body (both): `{ "x402Version": 2, "paymentPayload": <decoded X-PAYMENT>, "paymentRequirements": <the accepted entry> }`.

Responses: verify → `{ "isValid": boolean, "invalidReason"?: string, "payer"?: string }`; settle → `{ "success": boolean, "transaction": "<txId>", "network": "..." , "errorReason"?: string }`. The settle response, base64-encoded, becomes `X-PAYMENT-RESPONSE`.

**Confirmed Sept 10 (first real exchange, TestNet):** the facilitator accepted our `X-PAYMENT` exactly as documented above — `{x402Version: 2, scheme, network, payload: {paymentGroup: [<base64 msgpack signed txn>], paymentIndex: 0}}` with a single plain `AssetTransferTxn` (no fee payer, no group) — and `/verify` **simulates the transaction** before answering. An unfunded payer came back as `isValid: false` with `invalidReason` = `"Transaction simulation failed: transaction <txid>: overspend (account …, MicroAlgos:0 …)"`, which our gateway surfaced in the 402's `error`. So: shapes are right; payer needs ALGO for the fee/min-balance and USDC ≥ amount.

## Discovery ("Bazaar") and the challenge tag

- **Tag:** add `"tag": "x402-global-challenge"` inside `extra` of every payment-requirements entry.
- **Discovery extension:** add an `extensions` object to the 402 body:

```json
{
  "x402Version": 2,
  "accepts": [ { "...": "...", "extra": { "decimals": 6, "tag": "x402-global-challenge" } } ],
  "extensions": {
    "bazaar": {
      "info": {
        "input":  { "type": "http", "method": "POST", "params": { "url": "string" } },
        "output": { "example": { "markdown": "# …", "title": "…" }, "schema": { "type": "object" } }
      },
      "schema": { "$comment": "JSON Schema that validates info" }
    }
  }
}
```

  The client copies `extensions` into the payment payload; the facilitator catalogs the resource when it **settles** — there is no registration call. Confirm the exact `info`/`schema` shape against `@x402-avm/extensions` (`declareDiscoveryExtension()`) during the spike and paste the real JSON here.
- The requirement's `description` is the catalog text: concrete, say what the caller gets.
- The Bazaar also enriches from the endpoint's OpenGraph tags, `llms.txt`, well-known files, and the merchant NFD.
- Catalogs: `https://facilitator.goplausible.xyz/discovery/resources`, `/discovery/merchants`. Leaderboard: `/dashboard/leaderboards`.
- **One payTo per domain**, opted in to USDC; never reuse it on another domain.

## Wallets for Phase 0

- Gateway receiving wallet (Defly, created Sept 9 2026), address = `payTo`:
  `UTWS33TM7IT7NINJSFWS5KVGL73G4ERJMYDKHF7KE4WDXHYO4L7V2PNMRE`
  Public address only — the mnemonic lives in the password manager. Lives in Rails credentials as `algorand.pay_to`; read it with `Rails.application.credentials.dig(:algorand, :pay_to)`. It must **opt in** to the USDC ASA on each network before it can receive.
- Agent (payer) wallet in Defly (created Sept 10 2026), address:
  `ABEAGNREVBDSINTSOWXYXOANZDRTLBWDGULA3SALTWRMXNEED2LWZNSADE`
  Public address only; holds the TestNet USDC from Circle's faucet. It funds the *spike payer* below with ordinary Defly sends, so no phone mnemonic is ever typed anywhere.
- Spike payer: a throwaway TestNet account generated on the dev machine by `bin/agent-wallet` (mnemonic written straight into `gateway/.env.local`, never printed). `bin/pay` signs with it. Separate account (its mnemonic must be on the machine running the spike client — `gateway/.env.local`, git-ignored, copy in the password manager; optionally imported into Defly/Pera for viewing). Funded with TestNet ALGO (dispenser) and TestNet USDC (Circle faucet).
- The gateway server holds **no private keys**; it only builds requirements and calls the facilitator.

## Sources

- GoPlausible facilitator: https://facilitator.goplausible.xyz/ · https://facilitator.goplausible.xyz/supported
- GoPlausible Algorand x402 documentation: https://github.com/GoPlausible/.github/blob/main/profile/algorand-x402-documentation/README.md
- Algorand Foundation — enabling x402 payments best practices: https://algorand.co/blog/enabling-x402-payments-on-algorand-a-best-practices-guide
- Global x402 Challenge: https://algorand.co/global-x402-challenge · how to build & submit: https://algorand.co/blog/the-x402-global-challenge-is-live-how-to-build-submit-your-entry · demo server: https://github.com/algorandfoundation/x402-demo/tree/main/x402-basic-tutorial · Bazaar extension examples: https://github.com/GoPlausible/.github/blob/main/profile/algorand-x402-documentation/typescript/x402-avm-extensions-examples.md
- x402 origin (Coinbase): https://www.coinbase.com/developer-platform/discover/launches/x402
