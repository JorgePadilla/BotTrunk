# gateway — Rails conventions

Rails 8.1 · Postgres · Solid Queue/Cache/Cable · Hotwire · Tailwind v4 + daisyUI v5 (vendored `app/assets/tailwind/*.mjs`) · ViewComponent + Lookbook · rails_icons (Lucide) · Minitest. Full list and rationale: `../docs/stack.md`.

## Layers (top → bottom)

Rack middleware (`app/middleware/x402_paywall.rb`) → controllers (thin) → services (`app/services/<domain>/`, all business logic, return `Result`) → adapters (`app/services/payments/adapters/`, `app/services/upstream/`) → models. Components never query the DB. Details: `../docs/architecture.md`.

Detailed rules load by path from `../.claude/rules/`: `services.md`, `ui.md`, `payments.md`, `testing.md`.

## Commands

```
bin/setup                                           # bundle, db:prepare
bin/rails rails_icons:install --libraries=lucide    # once
bin/dev                                             # server + tailwind watcher
bin/rails test  ·  bin/rails test:system            # unit/integration · browser
bin/rubocop && bin/brakeman
http://localhost:3000/lookbook?theme=bottrunk-dark  # component previews
```

## Now

`Catalog::Service` is an in-memory PORO (`app/models/catalog/service.rb`) until the schema lands; keep its reader interface when replacing it with ActiveRecord.
