# Architecture

## 1. Shape

BotTrunk is one Rails monolith (`gateway`) plus one thin, stateless sidecar (`mcp-hub`). The monolith owns all state and all money logic. The sidecar is a translation layer: it turns the catalog into MCP tools so agents can discover and pay for services from inside their own framework.

```
┌──────────────── agents ────────────────┐      ┌──── sellers ────┐
│ Claude / GPT / LangChain / x402 clients │      │ browser          │
└───────┬────────────────────┬───────────┘      └────────┬────────┘
        │ MCP                │ HTTP + X-PAYMENT           │ Hotwire
   ┌────▼─────┐        ┌─────▼──────────────────────────────▼────┐
   │ mcp-hub  │ ─JSON─▶│ gateway (Rails 8.1)                      │
   │ (TS)     │        │  Rack: X402Paywall                        │
   └──────────┘        │  Controllers → Services → Adapters → DB  │
                       └─────┬───────────────┬────────────────────┘
                             │ Faraday       │ Faraday
                     ┌───────▼──────┐  ┌─────▼──────────┐
                     │ facilitator  │  │ upstream APIs   │
                     │ (GoPlausible)│  │ (sellers' code) │
                     └──────────────┘  └────────────────┘
```

## 2. Layers inside `gateway`

| Layer | Lives in | Knows about | Must not |
|---|---|---|---|
| Rack middleware | `app/middleware/` | headers, status codes, `Payments::*` services | touch models directly |
| Controllers | `app/controllers/` | params, one service, rendering | contain business rules |
| Services | `app/services/<domain>/` | models, adapters, other services | render, know about HTTP headers (except `payments/`) |
| Adapters | `app/services/payments/adapters/`, `app/services/upstream/` | external APIs (facilitator, chains, upstream) | be called from controllers |
| Models | `app/models/` | persistence, validations, scopes | call external systems |
| Components | `app/components/` | presentation of models/POROs handed to them | query the database |

`Result` (`app/services/result.rb`) is the contract between layers: `Result.success(data)` / `Result.failure(error, code:)`, with `success?`, `failure?`, `data`, `error`, `code`.

## 3. Domain model (Phase 1 target)

```
Seller ──< Service ──< Endpoint          Endpoint = one paid URL: path, method, price (µUSDC), upstream URL
                │
                └──< Call ──── Payment    Call = one request through the paywall (timing, status, upstream code)
                                 │        Payment = the x402 payment for that call (network, asset, amount, tx id, state)
Seller ──< Payout                         Payout = money out to the seller (sum of settled Payments − commission)
Agent  ──< ApiKey, Credit                 Phase 2: non-crypto path (card-bought credits)
```

Money rules: every amount is an integer in atomic units (µUSDC = 10⁻⁶). Commission rate lives on `Service` (default 12%, range 10–15%). A `Call` is immutable once settled; corrections are new rows.

Until the schema exists, `Catalog::Service` (`app/models/catalog/service.rb`) is a PORO with the same reader interface the UI will keep using.

## 4. The paid-call request flow

```
POST /s/:slug/:path
  │
  ├─ X402Paywall#call(env)
  │    ├─ no X-PAYMENT ──▶ Payments::BuildRequirements(service, endpoint)
  │    │                     └─▶ 402, body {x402Version, accepts:[requirements], error}
  │    └─ X-PAYMENT ─────▶ Payments::DecodePaymentHeader  (base64 JSON → Payments::Payload)
  │                         Payments::VerifyPayment(payload, requirements)
  │                           └─▶ Adapters::Algorand#verify → POST facilitator /verify
  │                               failure ──▶ 402 again with error reason
  ▼
  Gateway::ProxyCall(endpoint, request)      Faraday → upstream, timeout from endpoint, timed
  │   upstream 5xx/timeout ──▶ do NOT settle; 502 to the agent; Call recorded as failed
  ▼
  Payments::SettlePayment(payload, requirements)   → /settle  (inline in Phase 0; SettlePaymentJob later)
  ▼
  Ledger::RecordTransaction(call, payment)         commission split, seller balance
  ▼
  200 + upstream body + X-PAYMENT-RESPONSE {success, transaction, network}
```

Invariants: verify before spending upstream compute; settle only after a successful upstream response; never hold funds — the facilitator moves them, we record them.

## 5. Directory conventions

```
app/
  components/
    application_component.rb
    ui/          button pill card tabs search_input navbar theme_toggle  (modal alert empty_state later)
    catalog/     service_card price filter_chips pay_panel
    docs/        code_snippet schema_table
    gateway/     call_timeline
    dashboard/   (Phase 1) stat_row calls_table earnings_chart endpoint_form api_key_reveal
  services/
    result.rb
    catalog/     search.rb
    services/    register_service.rb publish_service.rb
    payments/    build_requirements.rb decode_payment_header.rb verify_payment.rb settle_payment.rb
                 requirements.rb payload.rb receipt.rb        (value objects)
                 adapters/base.rb adapters/algorand.rb          (adapters/base_evm.rb later)
    gateway/     proxy_call.rb
    upstream/    client.rb
    ledger/      record_transaction.rb
    payouts/     create_payout.rb
  middleware/    x402_paywall.rb
  jobs/          settle_payment_job.rb payout_job.rb health_check_endpoint_job.rb
```

Class ↔ file: `Payments::VerifyPayment` → `app/services/payments/verify_payment.rb`. Zeitwerk does the rest; no `require`s.

## 6. mcp-hub

TypeScript, `@modelcontextprotocol/sdk`, stateless. On start (and every N minutes) it fetches `GET /api/v1/catalog` from the gateway and registers one MCP tool per endpoint (`scrape_markdown`, `pdf_extract`, …) with the input schema and price in the tool description. Calling a tool performs the x402 flow against the gateway using the agent's configured wallet. It never talks to the database and never holds keys server-side beyond the agent's own configuration.

## 7. Cross-cutting

- **Jobs:** Solid Queue. Anything that talks to the facilitator after the response is sent, payouts, health checks.
- **Rate limiting:** rack-attack in front of the paywall; unpaid 402 probes are cheap but not free.
- **Observability:** Rails structured logging with `request_id`, `call_id`, `tx_id` tags; the `calls` table is the audit log.
- **Security:** secrets in Rails credentials; wallet mnemonics never on the server (the gateway only *receives*); CSP on; `allow_browser versions: :modern`.
- **i18n:** English first; `es` locale added when the seller UI opens to LATAM developers.
