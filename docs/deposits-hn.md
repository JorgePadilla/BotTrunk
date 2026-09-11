# Lempira deposits (deposit-bac-*) — how they work and how to run them

The first human-fulfilled, high-ticket service: an agent pays USDC, a person deposits lempiras into a **BAC Credomatic** account in Honduras within 24 hours. Four fixed tiers so the x402 price is known before the call: `deposit-bac-1000`, `-2500`, `-5000`, `-10000` (L1,000 minimum, L10,000 maximum per call; at most 3 settled deposits per beneficiary account per 24 h).

## Price

`USDC = amount_hnl ÷ (reference_rate − spread) × (1 + fee)` — rounded up to the µUSDC.

- **Reference rate:** `Rates::UsdHnl`, refreshed at most every six hours (four times a day), on demand, and stored in `exchange_rates`. Order: `HNL_PER_USD` (manual pin, wins outright) → the **Banco Central de Honduras Web API** (`Rates::FetchBch`; set `BCH_API_KEY` — free account at https://bchapi-am.developer.azure-api.net, subscribe to "Banco Central de Honduras - Web API", copy the primary key; indicator `BCH_TCR_INDICATOR_ID`, default 97 = Tipo de Cambio de Referencia; `bin/rails rates:bch_indicators` lists candidates) → the open.er-api.com feed → the newest stored rate (≤ 7 days) → a hard 26.00 fallback. `bin/rails rates:show` prints what pricing uses right now; `/admin/stats` shows it too.
- **Spread:** `HNL_RATE_SPREAD`, default **L1.50** per dollar below the reference — that is the exchange margin the buyer gives up.
- **Fee:** `DEPOSIT_FEE_BPS`, default **500** (5 %).

"Hourly" here means the next request after an hour triggers the refresh (there is no background worker yet); a settle takes the rate of the 402 the agent paid, which is at most an hour old.

Example at a 26.20 reference: L1,000 → 1000 ÷ 24.70 × 1.05 = **42.510122 USDC**. The catalog, the 402 and the Bazaar all show the day's number; it changes when the rate does.

## Flow

1. Agent `POST /s/deposit-bac-1000` with `beneficiary_name`, `account_number` (6–20 digits), optional `concept` and `contact_email` → 402 with today's price.
2. Agent retries with the payment. `Fulfillers::DepositBac` validates the input and opens a `DepositOrder` in `awaiting_payment`. Bad input → 422, limit hit → 429, **nothing charged** (`Gateway::HandlePaidCall` never settles a 4xx).
3. The USDC settles; the order becomes `pending`, linked to the `Call` row, and the agent gets `202 { order_id, status: "pending", eta: "within 24 hours", status_url }`.
4. The agent (or anyone with the token) polls `GET /orders/:order_id` — free, no bank details in the answer.
5. You open **/admin/orders**: the queue lists each pending deposit with beneficiary, account number, amount, what was paid and the on-chain txn. Make the BAC→BAC transfer in the BAC app, paste the receipt/reference number, **Mark delivered**. The status endpoint flips to `delivered` with the reference.
6. Cannot deliver (bank rejects the account, wrong name)? Send the USDC back to the payer address from the gateway wallet in Defly, paste the refund txn id, **Mark refunded**.

Orders whose payment never settled show under "Never paid" and cost nobody anything.

## Operating it

- **Float:** keep enough lempiras in the BAC account to cover a day of deposits (four L10,000 orders = L40,000). Sell USDC for lempiras on a regular cadence to refill it; the spread + fee is what pays for that off-ramp and the time.
- **Promise:** 24 hours. If you will be away, set the tiers to `coming_soon` in `Catalog::Service` (they answer 503 and cannot be bought) rather than missing the window.
- **Records:** every order keeps amount, rate, fee, payer address (via `calls`), receipt reference and timestamps. Account numbers are encrypted at rest (Active Record Encryption, deterministic so the daily limit can be counted). Production needs the keys in credentials: `bin/rails db:encryption:init` once, paste into `credentials.yml.enc`, redeploy.
- **Limits are deliberate:** L10,000 per order and 3 orders per account per day keep any single day's exposure small while this is one person with one bank app.
- **You are told, twice:** an email lands at `ADMIN_EMAIL` the moment a deposit settles (amount, beneficiary, masked account, link to the queue), and a digest at 07:00 lists anything still waiting with its age. If both are quiet and the queue is not empty, email is broken — check `SMTP_ADDRESS` and the Resend dashboard before assuming there is no work.
- **The buyer is told, if they left an address:** a receipt when the payment settles, and the bank reference when you mark it delivered, or the refund transaction if you refund. `contact_email` is optional, so an order without one is normal — the flash message after you press Deliver says whether anyone was emailed.
- **Account numbers are never emailed in full.** The alert shows the last four; the full number is in the queue, behind the admin password.

## Regulatory note (not legal advice)

Moving money for third parties in Honduras is a regulated activity: money remitters ("sociedades remesadoras") and payment institutions are supervised by the CNBS, and the anti-money-laundering law applies to anyone who does it habitually. Running deposits from a personal BAC account at volume can get the account frozen and the person questioned. Treat this as a **limited pilot** (small amounts, known beneficiaries, full records), talk to a Honduran lawyer before promoting it, and plan to move fulfilment behind a licensed partner (a remesadora or a bank's transfer API) if it takes off. The gateway already keeps the records a partner would ask for.
