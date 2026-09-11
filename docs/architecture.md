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
   │ (TS)     │        │  PaidCallsController → HandlePaidCall     │
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
  ├─ PaidCallsController#create ──▶ Gateway::HandlePaidCall  (ADR 0008)
  │    ├─ no X-PAYMENT ──▶ Payments::BuildRequirements(service)
  │    │                     └─▶ 402, body {x402Version, accepts:[requirements], extensions.bazaar, error}
  │    └─ X-PAYMENT ─────▶ Payments::Payload.from_header  (base64 JSON → Payments::Payload)
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
  controllers/
    catalog_controller.rb          GET /            GET /s/:slug          (HTML)
    paid_calls_controller.rb       POST /s/:slug                          (the x402 endpoint)
    pages_controller.rb            GET /docs /sell /sign_in
    seller_inquiries_controller.rb POST /sell                             (early-access form)
    api/v1/catalog_controller.rb   GET /api/v1/catalog[/:slug]            (JSON, read by mcp-hub)
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
    payments/    build_requirements.rb verify_payment.rb settle_payment.rb networks.rb
                 requirements.rb payload.rb receipt.rb        (value objects)
                 adapters/base.rb adapters/algorand.rb          (adapters/base_evm.rb later)
    gateway/     handle_paid_call.rb proxy_call.rb
    fulfillers/  scrape_markdown.rb            (BotTrunk's own services, run in-process; Catalog::Service#fulfiller)
    sellers/     create_inquiry.rb
    upstream/    client.rb
    ledger/      record_transaction.rb
    payouts/     create_payout.rb
  jobs/          settle_payment_job.rb payout_job.rb health_check_endpoint_job.rb
```

Class ↔ file: `Payments::VerifyPayment` → `app/services/payments/verify_payment.rb`. Zeitwerk does the rest; no `require`s.

## 6. mcp-hub

TypeScript, published to npm as **`bottrunk-mcp`** (`npx bottrunk-mcp`), stdio transport, stateless apart from two files under `~/.bottrunk/` on the agent's machine. On start it fetches `GET /api/v1/catalog` and registers one MCP tool per **live** service (`bottrunk_scrape_markdown`, …) with the catalog's input fields as the JSON schema and the price in the description, plus two free tools: `bottrunk_catalog` (discovery, includes coming-soon services) and `bottrunk_wallet` (address, balances, caps). A paid tool call goes through `@x402-avm/fetch` with an `ExactAvmScheme` per network (explicit algod URL — the scheme's default is TestNet) and a `ClientAvmSigner` built from the agent's key; the client copies `resource`, `accepted` and `extensions` from the 402 into the payload, so settles are tagged and Bazaar-cataloged like any other. Caps (`BOTTRUNK_MAX_PER_CALL`, `BOTTRUNK_MAX_PER_DAY`) are enforced in the client's `onBeforePaymentCreation` hook, before anything is signed; spend is tracked in `~/.bottrunk/spend.json` per UTC day.

Wallet: `npx bottrunk-mcp wallet` generates a 25-word account into `~/.bottrunk/wallet.json` (0600) or `BOTTRUNK_MNEMONIC` supplies one; `wallet optin` does the USDC opt-in. The gateway never sees the key. Tests (`npm test`, node:test) drive the real x402 client through an in-process fake gateway + fake algod, including one full 402 → signed ASA transfer → 200 round trip and the stdio transport.

Gateway side: `Catalog::Service#status` (`live` | `coming_soon`) is exposed by `/api/v1/catalog`; `POST /s/:slug` answers **503** for anything not live, before the 402, so placeholder services can be listed without ever charging anyone.

## 7. Cross-cutting

- **Jobs:** Solid Queue. Anything that talks to the facilitator after the response is sent, payouts, health checks.
- **Rate limiting:** rack-attack in front of the paywall; unpaid 402 probes are cheap but not free.
- **Observability:** Rails structured logging with `request_id`, `call_id`, `tx_id` tags; the `calls` table is the audit log.
- **Security:** secrets in Rails credentials; wallet mnemonics never on the server (the gateway only *receives*); CSP on; `allow_browser versions: :modern`.
- **i18n:** English first; `es` locale added when the seller UI opens to LATAM developers.
