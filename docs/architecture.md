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
    notifications/ deliver.rb announce_order.rb announce_order_update.rb announce_inquiry.rb daily_digest.rb
    mcp/         tools.rb dispatch.rb              (the hosted MCP endpoint, §6c)
  mailers/       application_mailer.rb deposit_mailer.rb admin_mailer.rb seller_mailer.rb   (§8b)
  jobs/          settle_payment_job.rb payout_job.rb health_check_endpoint_job.rb
```

Class ↔ file: `Payments::VerifyPayment` → `app/services/payments/verify_payment.rb`. Zeitwerk does the rest; no `require`s.

## 6. mcp-hub (local, with a wallet)

TypeScript, published to npm as **`bottrunk-mcp`** (`npx bottrunk-mcp`), stdio transport, stateless apart from two files under `~/.bottrunk/` on the agent's machine. On start it fetches `GET /api/v1/catalog` and registers one MCP tool per **live** service (`bottrunk_scrape_markdown`, …) with the catalog's input fields as the JSON schema and the price in the description, plus two free tools: `bottrunk_catalog` (discovery, includes coming-soon services) and `bottrunk_wallet` (address, balances, caps). A paid tool call goes through `@x402-avm/fetch` with an `ExactAvmScheme` per network (explicit algod URL — the scheme's default is TestNet) and a `ClientAvmSigner` built from the agent's key; the client copies `resource`, `accepted` and `extensions` from the 402 into the payload, so settles are tagged and Bazaar-cataloged like any other. Caps (`BOTTRUNK_MAX_PER_CALL`, `BOTTRUNK_MAX_PER_DAY`) are enforced in the client's `onBeforePaymentCreation` hook, before anything is signed; spend is tracked in `~/.bottrunk/spend.json` per UTC day.

Wallet: `npx bottrunk-mcp wallet` generates a 25-word account into `~/.bottrunk/wallet.json` (0600) or `BOTTRUNK_MNEMONIC` supplies one; `wallet optin` does the USDC opt-in. The gateway never sees the key. Tests (`npm test`, node:test) drive the real x402 client through an in-process fake gateway + fake algod, including one full 402 → signed ASA transfer → 200 round trip and the stdio transport.

Gateway side: `Catalog::Service#status` (`live` | `coming_soon`) is exposed by `/api/v1/catalog`; `POST /s/:slug` answers **503** for anything not live, before the 402, so placeholder services can be listed without ever charging anyone.

## 6c. Hosted MCP (`mcp.bottrunk.com`)

The same catalog, reachable as a **remote** MCP server for clients that cannot spawn a local command (ChatGPT, Claude on the web, hosted agent platforms). `McpController` (`ActionController::API`) answers `POST /mcp` with JSON-RPC 2.0 over the Streamable HTTP transport and hands the body to `Mcp::Dispatch`; `GET`/`DELETE` answer 405 with `Allow: POST, OPTIONS`, and CORS is open because there is nothing to authorize.

Stateless on purpose: the 2026-07-28 revision of the transport removed protocol-level sessions and the GET stream, and every tool answers in one round trip, so there is no session id and no SSE. `initialize` is still answered for older clients (2025-03-26 … 2025-11-25) and their `Mcp-Session-Id` is ignored; a notification (no `id`) answers **202 with no body**. Unknown methods answer 200 with `-32601` rather than the spec's 404, because today's clients handle a JSON-RPC error better than a bare 404.

`Mcp::Tools` exposes five tools, all free and read-only: `bottrunk_catalog`, `bottrunk_service`, `bottrunk_payment_instructions` (the live 402 requirements for a slug — price, network, asset, `payTo`, fee payer), `bottrunk_quote_deposit` and `bottrunk_order_status`. **A hosted server cannot hold an agent's wallet, so it never spends.** That is the whole design constraint: MCP has no payment channel in a tool call, and we will not custody keys. An agent that can sign gets its quote here and answers the endpoint's own 402 directly; an agent that cannot runs `npx bottrunk-mcp` locally (§6), where the key lives on its own machine. Calls are tracked as `mcp_call` events (§8).

## 6b. The catalog

`Catalog::Service` is still an in-memory list (`app/models/catalog/service.rb`). Each entry carries a `status` — **live** (priced, callable, in the Bazaar) or **on_request** (real work we do, arranged by email; `POST /s/:slug` answers 503 so nothing can be charged) — and optionally a `family` (`deposit-bac`), which collapses the four deposit tiers into one catalog card while staying four separate Bazaar resources. `Catalog::Service.extra` is a test-only hook for services the public catalog does not have (a proxied one, a not-live one).

BotTrunk's own services are `Fulfillers::*`, all subclasses of `Fulfillers::Base`, which owns the SSRF guard (a host resolving to private space is refused before any request), the Faraday client, and the Result shapes: a 4xx is `Result.success` with that status (answered, never settled), a genuine upstream failure is `Result.failure`. Today: `ScrapeMarkdown`, `PageMetadata`, `ExtractLinks`, `UrlHealth`, `DomainDns` (all code, no dependencies beyond Nokogiri and stdlib Resolv/OpenSSL) and `DepositBac` (human-fulfilled, §7).

`Catalog::Metrics` reads the `calls` ledger — count, median upstream latency (`percentile_cont`), success rate, volume, last call — cached 60 s, and `combined` merges a family's rows. Nothing on the site claims a latency or success rate that was not measured; a service with no calls shows none. The catalog page also shows totals when there is real traffic.

`/connect` is the setup page for twelve agent clients (Claude Code and Desktop, Cursor, VS Code, Cline, Windsurf, Zed, OpenClaw, Hermes Agent, Goose, the OpenAI Agents SDK, LangChain). The list lives in `app/models/docs/mcp_client.rb`: every snippet is copied from that client's own documentation and carries a `docs_url` to it, so when a client changes its config format the fix is one entry.

## 7. Human-fulfilled orders (lempira deposits)

`deposit-bac-*` are catalog entries with `price_hnl` instead of `price_usdc`: `Catalog::Service#price_atomic` derives the USDC price from `Pricing::LempiraDeposit` (reference rate from `Rates::UsdHnl`, minus a spread, plus a fee — all env-tunable). The fulfiller `Fulfillers::DepositBac` runs in the normal paid loop *before* settlement: it validates the input, enforces the per-account daily limit and opens a `DepositOrder` in `awaiting_payment`, answering 202 with an order token. `Gateway::HandlePaidCall` then settles and moves the order to `pending` (linked to the `Call`), or cancels it if settlement fails; **a 4xx from any service is passed through and never settled**. A person clears the queue at `/admin/orders` (deliver with the bank receipt reference, or refund with the USDC refund txn); agents poll `GET /orders/:token`. Runbook and the regulatory note: `docs/deposits-hn.md`.

## 8. Analytics and the admin dashboard

First-party and cookieless. `Analytics::Track` writes one `events` row per page view (`page_view`), catalog API hit (`catalog_api`), 402 probe (`payment_required`), rejected payment (`payment_rejected`) or hit on a not-yet-live service (`coming_soon`). It stores a coarse `client` label derived from the user agent (`bottrunk-mcp`, `x402-client`, `curl`, `python`, `node`, `browser`, `bot`), the referrer host, a `visitor` hash that rotates daily (SHA-256 of ip + ua + date + secret, truncated), and a coarse location (ISO country + "City, Region") from a local MaxMind GeoLite2 database (`Analytics::Geolocate`; `bin/geoip-update` downloads it at boot when `MAXMIND_LICENSE_KEY` is set, no network call per request) — never the IP or the raw user agent. Settled payments are not events; `calls` is the ledger and the source of truth for money. Tracking is best-effort: the service rescues everything and logs, so a broken analytics insert can never fail a request. Controllers call it through the `TracksEvents` concern (`after_action :track_page_view` on public pages; `PaidCallsController#track_paywall` for 402s).

`GET /admin/stats` (HTTP basic auth, password from `ADMIN_PASSWORD` or credentials `admin.password`; no password means no access) renders `Stats::Overview`: rolling windows (24 h / 7 d / 30 d / all time) of views, visitors, probes, rejected payments, settled calls, unique payers, volume and commission; per-day bars; per-service rows; top referrers, pages and API clients; the last 20 settled calls (linked to allo.info) and probes. Components live in `app/components/dashboard/` (`StatRowComponent`, `DailyBarsComponent` — inline SVG, no chart library — and `TableComponent`).

## 8b. Transactional email

Plain Action Mailer over SMTP — no gem, no vendor SDK, so changing provider is four environment variables. Today that is Resend (`smtp.resend.com`, user `resend`, password = API key). **Without `SMTP_ADDRESS` the app logs a warning and delivers nothing**, which is what a fresh deploy or a forked repo should do.

Four recipients, three mailers:

| Mailer | When | To |
|---|---|---|
| `DepositMailer#received` | a deposit settles and joins the queue | the buyer, if `contact_email` was supplied |
| `DepositMailer#delivered` / `#refunded` | someone clears it at `/admin/orders` | the buyer |
| `AdminMailer#new_order` | a deposit settles | `ADMIN_EMAIL` |
| `AdminMailer#new_inquiry` + `SellerMailer#acknowledgement` | a `/sell` form is submitted | `ADMIN_EMAIL`, and the seller |
| `AdminMailer#digest` | 07:00 Honduras, by the `bottrunk-digest` cron | `ADMIN_EMAIL` |

`contact_email` is optional on purpose: an agent with a wallet has no inbox, and the order token plus `GET /orders/:token` is the authoritative receipt. A mailer with no recipient builds a `NullMail` and nothing is queued. Likewise every `AdminMailer` returns early when `ADMIN_EMAIL` is unset — these never guess an address.

**Bank account numbers are masked to the last four in every email.** They are encrypted at rest, mail is not a private channel, and the full number lives behind the admin password where the transfer is actually made.

`Notifications::Deliver` is the only thing that calls `deliver_later`, and it swallows everything: a settled payment is irreversible on-chain long before we try to tell anyone about it, so a mail server having a bad afternoon must never become an error for the payer. `Notifications::AnnounceOrder`, `AnnounceOrderUpdate`, `AnnounceInquiry` and `DailyDigest` decide *who* hears about *what*; the call sites (`Gateway::HandlePaidCall`, `Admin::OrdersController`, `Sellers::CreateInquiry`) name one service and move on.

Active Job runs in the web process (`:async`). Mail is best-effort and low-volume; a worker service and a durable queue are for work that must survive a restart, which a receipt is not. Every email has an HTML and a text part, table-based and inline-styled — `app/views/layouts/mailer.*`. Previews for all of them, with no database writes: `/rails/mailers` in development, or `bin/rails mail:preview` to send one of each to `ADMIN_EMAIL` from real records.

## 9. Cross-cutting

- **Jobs:** Active Job on the `:async` adapter today (email only, §8b). Solid Queue and a worker service when something has to survive a restart: payouts, retrying facilitator calls, health checks.
- **Rate limiting:** rack-attack in front of the paywall; unpaid 402 probes are cheap but not free.
- **Observability:** Rails structured logging with `request_id`, `call_id`, `tx_id` tags; the `calls` table is the audit log; `events` + `/admin/stats` for traffic (§7).
- **Security:** secrets in Rails credentials; wallet mnemonics never on the server (the gateway only *receives*); CSP on; `allow_browser versions: :modern`.
- **i18n:** English first; `es` locale added when the seller UI opens to LATAM developers.
