# Deploying the gateway (Render)

**Status (Sept 10, 2026):** live at https://bottrunk-gateway.onrender.com (service `srv-dahjcb6q1p3s73dqem4g`, Ohio; Postgres 18 `bottrunk-db`). First blueprint deploy succeeded on the first try (2m03s). Custom domains live since Sept 10: **https://bottrunk.com** (site), **https://api.bottrunk.com** (same service), `www` → apex. DNS at Namecheap: `A @ 216.24.57.1`, `CNAME www` and `CNAME api` → `bottrunk-gateway.onrender.com`. **MainNet since Sept 11, 2026** (`ALGORAND_NETWORK=mainnet` in `render.yaml`; gateway wallet opted in to USDC `31566704`).

One Docker web service + one Postgres, described in `render.yaml` at the repo root. ~$13/month (Starter web $7 + Basic Postgres $6). Decided Sept 10, 2026 over Fly (managed Postgres there starts at $38) and Kamal on a VPS (ops time we don't have before the challenge deadline).

## First deploy (once, ~30 min)

1. **Render account** → New → **Blueprint** → connect `JorgePadilla/BotTrunk` → Render reads `render.yaml` and proposes `bottrunk-gateway` + `bottrunk-db`. Apply.
2. When it asks for `RAILS_MASTER_KEY`, paste the contents of `gateway/config/master.key` (the one in your password manager). `MAXMIND_LICENSE_KEY` (free GeoLite2 account at maxmind.com → *Manage License Keys*) turns on country/city in `/admin/stats`; `bin/render-start` downloads the database at boot when it is set. `ADMIN_PASSWORD` is the other secret: any long random string; it is the HTTP basic-auth password for `/admin/stats` (user name is ignored — type `admin`). Leave it empty and the admin routes answer 401 to everyone. `DATABASE_URL` is injected from the database, the rest are plain values in the blueprint. For the lempira deposits (`docs/deposits-hn.md`) the credentials also need Active Record Encryption keys: run `bin/rails db:encryption:init` locally once and paste the three keys into `bin/rails credentials:edit` (they ride along with `RAILS_MASTER_KEY`); without them a deposit request fails with a 500 at order creation.
3. First build takes ~5 min (Docker image, `assets:precompile`). The entrypoint runs `db:prepare` on boot, so migrations apply automatically. Health check is `GET /up`.
4. Open the `*.onrender.com` URL: catalog, `/docs`, and `curl -X POST …/s/scrape-markdown` must return a 402 with `payTo` = the gateway wallet.

## Domain

- Render → service → Settings → Custom Domains → add `api.bottrunk.com` and `bottrunk.com` (+ `www`). Render shows the CNAME target and issues TLS automatically.
- DNS (Namecheap, or Cloudflare if we move the zone there — free, recommended so the apex `bottrunk.com` can CNAME-flatten):
  - `api` → CNAME → `<service>.onrender.com`
  - `mcp` → CNAME → `<service>.onrender.com` (the hosted MCP endpoint; custom domain #3, so Render bills $0.25/mo for it)
  - `www` → CNAME → `<service>.onrender.com`
  - apex `@` → Render gives an A record / ALIAS instructions in the same screen.
- `config.hosts` in `production.rb` lists exactly these hosts (plus `*.onrender.com`); add any new domain there first or Rails answers 403.

## Going to MainNet (the challenge requirement)

1. In Defly, switch the **gateway** account (`UTWS…MRE`) to MainNet, fund it with a few ALGO, **opt in to USDC `31566704`** (0.1 ALGO min balance + fee).
2. The service is blueprint-managed: change `ALGORAND_NETWORK` in `render.yaml` and push (a dashboard edit would be overwritten on the next blueprint sync). `payTo` stays the same address — one wallet, two networks.
3. `curl` the 402 again: `network` must now be `algorand:wGHE2Pwdvd7S12BL5FaOP20EGYesN73ktiC1qzkkit8=` and `asset` `31566704`.
4. First real payment: the spike payer (`bin/agent-wallet`) uses the same key on both networks. `ALGORAND_NETWORK=mainnet bin/agent-wallet` shows its MainNet balances; send it ~0.5 ALGO and 1–2 USDC from Defly (gateway or second wallet), `ALGORAND_NETWORK=mainnet bin/agent-wallet optin`, then `BOTTRUNK_URL=https://api.bottrunk.com bin/pay` (the client follows whatever network the 402 announces). Keep only small amounts on this hot key.
5. Check https://facilitator.goplausible.xyz/dashboard/transactions (MAINNET) and `/dashboard/leaderboards`: BotTrunk should appear as a merchant with the `api.bottrunk.com` resource, and the Bazaar (`/discovery/resources`) should list the service with its description and schema.

## Incident log

- **Sept 10, 2026 — first paid call on api.bottrunk.com returned 500.** Cause: no `calls` table in production; the Docker entrypoint's `db:prepare` never ran under Render's start command. The facilitator had already settled TestNet txn `CCBCWALZMR74D4IQWQTLLA3RENS2R246MAZABGNMOCWYY2A6UBEQ` (0.005 USDC, payer `LQAWG…KPFQ`) before the ledger write crashed, so that payment exists on-chain with no `calls` row. A second attempt before the fix was deployed did the same: txn `3FVCICVJGRNASJI6QAIU5V7JWCKIS267OTHEG23BHO7IRNOPS6JA` (0.005 USDC). Both are TestNet; nothing to reconcile in real money. After the fix deployed, txn `CEIJ37A3UO5QBWMN62W5KQC3DHJR7HWHJBMTJSUBLSQUYS4AJS6Q` completed cleanly: 200, receipt, real markdown from the built-in scraper — the first paid call served from api.bottrunk.com. Fixes: `bin/render-start` + `preDeployCommand` run migrations; `Gateway::HandlePaidCall#record` shields the ledger so a settled call can never 500 (test added).

## Every later deploy

`git push` to `main` → Render builds and deploys (`autoDeploy: true`). Migrations run on boot. Roll back from the Render dashboard (Deploys → previous → Rollback) if needed.

## Email (Resend)

Delivery is plain SMTP, so the provider is four environment variables and nothing in the Gemfile. Without `SMTP_ADDRESS` the app logs a warning and sends nothing — that is the safe default, not a bug.

1. Create the account at resend.com and add the domain `bottrunk.com` (region us-east-1). Resend shows the records to add.
2. Add them at Namecheap → Domain List → bottrunk.com → Advanced DNS. Added on Sept 12, 2026:

   | Type | Host | Value |
   |---|---|---|
   | TXT | `resend._domainkey` | the 218-character DKIM key Resend shows (`p=MIGfMA0GCSqGSIb3…QIDAQAB`) |
   | CNAME | `rsend` | `rsend.forge.rmta.net` |
   | CNAME | `send` | `send.forge.rmta.net` |
   | TXT | `_dmarc` | `v=DMARC1; p=none;` (optional, added — monitor-only, changes nothing about delivery) |

   **Do not touch the existing `@` TXT record** (`v=spf1 include:spf.efwd.registrar-servers.com ~all`, under Mail Settings). That is the email *forwarding* for hello@bottrunk.com and it is unrelated to sending. Resend's SPF rides on the `send` subdomain, so the two never collide.

   Namecheap's UI truncates long values on screen — after saving, confirm the DKIM record is the full 218 characters and ends in `QIDAQAB`, not a shortened copy.
3. Back in Resend, press **Verify DNS Records**. Status goes Pending while it looks; Namecheap usually propagates within minutes.
4. Create an API key (sending permission only) and paste it into Render as `SMTP_PASSWORD` on **both** `bottrunk-gateway` and `bottrunk-digest`. Set `ADMIN_EMAIL` on both as well — that is where deposit alerts and the digest go. Everything else (`SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USER_NAME`, `MAIL_FROM`, `MAIL_REPLY_TO`) is already in `render.yaml`.
5. Check it: `bin/rails mail:preview` sends one of each email to `ADMIN_EMAIL`, rendered from the newest real records. Nothing is written.

`bottrunk-digest` is a Render cron job on the same image, running `bin/rails mail:digest` at `0 13 * * *` — 07:00 in Honduras, which is UTC-6 all year. It is billed per second of runtime, so a ten-second job a day costs pennies. Free tier at Resend is 3,000 emails a month, 100 a day; at current volume that is years of headroom, and the ceiling to watch is the *daily* one if a scraper ever starts opening deposits in a loop.

Deliverability notes: the from address is `no-reply@bottrunk.com` and replies go to `hello@bottrunk.com`, which Namecheap forwards to a real inbox — so a customer hitting Reply reaches a person. Bounces and complaints show in the Resend dashboard; nothing in the app reads them yet.

## Not yet configured (Phase 1+)

- Solid Queue / Solid Cache / Solid Cable: gems are installed but no schemas exist; `database.yml` production is a single primary and `cable.yml` uses `async`. Active Job runs on the `:async` adapter, which is fine for email; add Solid Queue and a worker when async settlement lands (`SettlePaymentJob`) or when a lost job would cost money.
- Error tracking (Sentry/Honeybadger) — worth adding before real traffic.
