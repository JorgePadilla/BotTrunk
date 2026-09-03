# gateway

The Rails 8.1 app behind bottrunk.com: service registry, x402 paywall + proxy, public catalog, seller dashboard.

## First run

    cd gateway
    bundle install
    bin/rails rails_icons:install --libraries=lucide   # downloads the Lucide SVGs into app/assets/svg/icons
    bin/setup                                          # db:prepare, clears logs/tmp
    bin/dev                                            # Rails on :3000 + tailwind watcher

Then open:

- http://localhost:3000 — the public catalog (in-memory seed data for now, see `app/models/catalog/service.rb`)
- http://localhost:3000/s/scrape-markdown — a service page
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

Conventions: see `../CLAUDE.md`.
