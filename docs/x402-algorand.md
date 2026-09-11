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

Amounts are strings in **atomic units**: `$0.09` USDC = `"90000"`.

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
      "amount": "90000",
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

## The v2 payment payload — where the tag, resource and extension really travel

Learned the hard way on Sept 11: three MainNet settles landed with a perfect 402 (Doctor all green) and were **still** untagged, unlisted and shown under the bare address. The facilitator reads the resource URL, the challenge tag and the discovery extension from the **PaymentPayload** (x402 v2 spec), not from the `paymentRequirements` we post:

```json
{
  "x402Version": 2,
  "resource": { "url": "https://api.bottrunk.com/s/scrape-markdown", "description": "…", "mimeType": "application/json" },
  "accepted": { "scheme": "exact", "network": "algorand:…", "amount": "90000", "asset": "31566704", "payTo": "…", "maxTimeoutSeconds": 60, "extra": { "decimals": 6, "tag": "x402-global-challenge", "feePayer": "…" } },
  "payload": { "paymentGroup": ["<base64 msgpack signed txn>"], "paymentIndex": 0 },
  "extensions": { "bazaar": { "info": …, "schema": … } }
}
```

Strict v2 clients build this themselves. Our gateway (`Payments::Adapters::Algorand#envelope`) fills `resource`, `accepted` and `extensions` when a payer omitted them, so v1-style clients (`X-PAYMENT` with only `payload`) are still tagged and cataloged. The 402 body likewise carries a top-level `resource` object per spec (`accepts[]` keeps the resource fields too, for older clients). `paymentRequirements` in the facilitator request is the spec shape (`Requirements#to_spec_h`, no resource fields).

## `/verify` and `/settle`

Request body (both): `{ "x402Version": 2, "paymentPayload": <decoded X-PAYMENT>, "paymentRequirements": <the accepted entry> }`.

Responses: verify → `{ "isValid": boolean, "invalidReason"?: string, "payer"?: string }`; settle → `{ "success": boolean, "transaction": "<txId>", "network": "..." , "errorReason"?: string }`. The settle response, base64-encoded, becomes `X-PAYMENT-RESPONSE`.

**Confirmed Sept 10 (first real exchange, TestNet):** the facilitator accepted our `X-PAYMENT` exactly as documented above — `{x402Version: 2, scheme, network, payload: {paymentGroup: [<base64 msgpack signed txn>], paymentIndex: 0}}` with a single plain `AssetTransferTxn` (no fee payer, no group) — and `/verify` **simulates the transaction** before answering. An unfunded payer came back as `isValid: false` with `invalidReason` = `"Transaction simulation failed: transaction <txid>: overspend (account …, MicroAlgos:0 …)"`, which our gateway surfaced in the 402's `error`. So: shapes are right; payer needs ALGO for the fee/min-balance and USDC ≥ amount.

## Headers (x402 v2 names — learned from the facilitator's x402 Doctor, Sept 11)

| Direction | v2 header | v1 alias we also honour |
|---|---|---|
| 402 challenge | `PAYMENT-REQUIRED` = base64 of the 402 JSON body (strict v2 clients read this, not the body) | — |
| client → server | `PAYMENT-SIGNATURE` = base64 payment payload | `X-PAYMENT` |
| server → client on success | `PAYMENT-RESPONSE` = base64 settlement receipt | `X-PAYMENT-RESPONSE` |

CORS for browser payers: `Access-Control-Allow-Origin: *`, allow `PAYMENT-SIGNATURE, X-PAYMENT` request headers, **expose** `PAYMENT-REQUIRED, PAYMENT-RESPONSE`, answer `OPTIONS`.

**PaymentPayload shape (v2), the one that bit us:** `{ x402Version, resource?, accepted, payload, extensions? }`. The scheme and the network live inside **`accepted`** — v2 has nothing named `scheme` at the top level; v1 did. `Payments::Payload` read only the top level, so every strict v2 client (including our own `bottrunk-mcp`) was refused with "scheme mismatch" before the facilitator was ever asked, while our Python spike — which sends the v1 flat shape — worked. The parser reads `accepted` first and falls back to the top level. The mcp-hub test suite asserted `accepted.network` on the way out and the Ruby suite asserted the flat shape on the way in: two halves of one repo agreeing with themselves and with nothing else. The fake gateway in `mcp-hub/src/test/fake_gateway.ts` now runs the real sanity checks so the seam is covered.

**Gasless:** advertise `extra.feePayer` = the facilitator's signer from `GET /supported` (`algorand:*` → `ZMFK2OI7ZBD2U27ISERZC4S6LKM6WMFJPZQ4MYNJDZ2VNBNMBA67RA22AA`, same on MainNet and TestNet). x402 clients then build an atomic group the facilitator co-signs, and the payer spends only USDC. A plain single transfer with the payer's own fee is still accepted.

## Discovery ("Bazaar") and the challenge tag

- **Tag:** add `"tag": "x402-global-challenge"` inside `extra` of every payment-requirements entry.
- **Discovery extension:** add an `extensions.bazaar` object to the 402 body, shaped exactly like `@x402/extensions` `createBodyDiscoveryExtension` (this passed the facilitator's x402 Doctor on Sept 11 — earlier guesses were rejected for: missing `schema`, `input.additionalProperties` not false, `input.type` not pinned by `const`):

```json
{
  "extensions": {
    "bazaar": {
      "info": {
        "input":  { "type": "http", "method": "POST", "bodyType": "json", "body": { "url": "https://example.com/pricing" } },
        "output": { "type": "json", "example": { "markdown": "# …", "title": "…", "word_count": 412 } }
      },
      "schema": {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "type": "object",
        "properties": {
          "input": {
            "type": "object",
            "properties": {
              "type": { "type": "string", "const": "http" },
              "method": { "type": "string", "enum": ["POST", "PUT", "PATCH"] },
              "bodyType": { "type": "string", "enum": ["json", "form-data", "text"] },
              "body": { "type": "object", "properties": { "url": { "type": "string", "description": "…" } } },
              "pathParams": { "type": "object" }
            },
            "required": ["type", "method", "bodyType", "body"],
            "additionalProperties": false
          },
          "output": {
            "type": "object",
            "properties": { "type": { "type": "string" }, "example": { "type": "object", "properties": { "…": {} } } },
            "required": ["type"]
          }
        },
        "required": ["input"]
      }
    }
  }
}
```

  Built by `Payments::BuildRequirements.bazaar_extension`; field examples come from `Catalog::Field#example`.
  The client copies `extensions` into the payment payload; the facilitator catalogs the resource when it **settles** — there is no registration call. **`schema` is mandatory**: the catalog validator rejects a `bazaar` extension whose `schema` is not an object (our first MainNet settle was not cataloged for exactly this reason — the Doctor at https://facilitator.goplausible.xyz/guide says so verbatim). `Payments::BuildRequirements::BAZAAR_SCHEMA` is the JSON Schema we ship for `info`.
- **Diagnose with the x402 Doctor** (Get started guide, "Check yourself"): paste the endpoint URL + method; it grades 402-first, header, CORS, fee payer, tag and both extensions with the same gate the catalog uses. 20 checks/day.
- The requirement's `description` is the catalog text: concrete, say what the caller gets.
- The Bazaar also enriches from the endpoint's OpenGraph tags, `llms.txt`, well-known files, and the merchant NFD.
- Catalogs: `https://facilitator.goplausible.xyz/discovery/resources`, `/discovery/merchants`. Leaderboard: `/dashboard/leaderboards`.
- **One payTo per domain**, opted in to USDC; never reuse it on another domain.

## Wallets for Phase 0

- Gateway receiving wallet (**Defly** on Jorge's phone, created Sept 9 2026), address = `payTo`:
  `UTWS33TM7IT7NINJSFWS5KVGL73G4ERJMYDKHF7KE4WDXHYO4L7V2PNMRE`
  Public address only — the mnemonic lives in the password manager. Lives in Rails credentials as `algorand.pay_to`; read it with `Rails.application.credentials.dig(:algorand, :pay_to)`. It must **opt in** to the USDC ASA on each network before it can receive.
- Second wallet, also in **Defly** on the phone (created Sept 10 2026) — funding/"bank" account for tests, address:
  `ABEAGNREVBDSINTSOWXYXOANZDRTLBWDGULA3SALTWRMXNEED2LWZNSADE`
  Public address only; holds the TestNet USDC from Circle's faucet. It funds the *spike payer* below with ordinary Defly sends, so no phone mnemonic is ever typed anywhere.
- Spike payer: a throwaway TestNet account generated on the dev machine by `bin/agent-wallet` (mnemonic written straight into `gateway/.env.local`, never printed). `bin/pay` signs with it. Separate account (its mnemonic must be on the machine running the spike client — `gateway/.env.local`, git-ignored, copy in the password manager; also imported into Defly on the phone for viewing — `LQAWG3WUMKWTFGEFCCOET6JGPRKD2JFYPIJ6HPIRYAC6QDUJSBDVMCKPFQ`). Funded with TestNet ALGO (dispenser) and TestNet USDC (Circle faucet).
- The gateway server holds **no private keys**; it only builds requirements and calls the facilitator.

## Sources

- GoPlausible facilitator: https://facilitator.goplausible.xyz/ · https://facilitator.goplausible.xyz/supported
- GoPlausible Algorand x402 documentation: https://github.com/GoPlausible/.github/blob/main/profile/algorand-x402-documentation/README.md
- Algorand Foundation — enabling x402 payments best practices: https://algorand.co/blog/enabling-x402-payments-on-algorand-a-best-practices-guide
- Global x402 Challenge: https://algorand.co/global-x402-challenge · how to build & submit: https://algorand.co/blog/the-x402-global-challenge-is-live-how-to-build-submit-your-entry · demo server: https://github.com/algorandfoundation/x402-demo/tree/main/x402-basic-tutorial · Bazaar extension examples: https://github.com/GoPlausible/.github/blob/main/profile/algorand-x402-documentation/typescript/x402-avm-extensions-examples.md
- x402 origin (Coinbase): https://www.coinbase.com/developer-platform/discover/launches/x402
