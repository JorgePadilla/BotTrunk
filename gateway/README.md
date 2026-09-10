# gateway

The Rails 8.1 app behind bottrunk.com: service registry, x402 paywall + proxy, public catalog, seller dashboard.

## First run

    cd gateway
    bundle install
    bin/rails rails_icons:install --library=lucide   # downloads the Lucide SVGs into app/assets/svg/icons
    bin/setup                                          # db:prepare, clears logs/tmp
    bin/dev                                            # Rails on :3000 + tailwind watcher

Then open:

- http://localhost:3000 — the public catalog (in-memory seed data for now, see `app/models/catalog/service.rb`)
- http://localhost:3000/s/scrape-markdown — a service page
- http://localhost:3000/docs — developer docs, rendering the live 402 body
- http://localhost:3000/sell — seller page with the early-access form (`seller_inquiries` table)
- http://localhost:3000/api/v1/catalog — the catalog as JSON (what `mcp-hub` will read)
- http://localhost:3000/lookbook — every ViewComponent, with a `theme` param to preview `bottrunk-dark`

## Where things are

| What | Where |
|---|---|
| Theme tokens (daisyUI v5) | `app/assets/tailwind/application.css` |
| daisyUI plugin (standalone, no npm) | `app/assets/tailwind/daisyui.mjs`, `daisyui-theme.mjs` |
| Fonts (Geist, SIL OFL) | `public/fonts/` |
| Components | `app/components/{ui,catalog,docs,gateway}/` |
| Component previews | `test/components/previews/` |
| Stimulus controllers | `app/javascript/controllers/` |
| Catalog seed (temporary PORO) | `app/models/catalog/service.rb` |

## The paid endpoint (Phase 0 spike)

    bin/rails db:prepare                      # creates the `calls` table
    bin/rails test                            # whole loop with a fake adapter + WebMock, no network
    curl -i -X POST localhost:5000/s/scrape-markdown -H 'Content-Type: application/json' -d '{"url":"https://example.com"}'
    # → 402 with `accepts[]` (payTo from credentials `algorand.pay_to`) and `extensions.bazaar`
    # scrape-markdown is a built-in service (Fulfillers::ScrapeMarkdown, in-process); the other seed
    # services still proxy to httpbin until they get real upstreams.

Pay it for real on TestNet with the payer wallet:

    bin/agent-wallet          # creates a throwaway TestNet payer on this machine, prints its address
    #  → from Defly send it 0.5 ALGO, then:
    bin/agent-wallet optin    # opts in to TestNet USDC
    #  → from Defly send it a few USDC, then:
    bin/pay                   # 402 → sign → retry against localhost:5000/s/scrape-markdown

Flow and files: `docs/architecture.md` §4 and ADR 0008. Every value we learn from the real facilitator goes into `docs/x402-algorand.md`.

Conventions: see `../CLAUDE.md`.
