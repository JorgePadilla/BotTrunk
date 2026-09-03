# Stack — what we use and why

Principle: a solo developer at 5–10 hrs/week cannot afford surface area. Every dependency must remove more work than it adds, and Rails defaults win ties.

## Runtime

| Piece | Choice | Why |
|---|---|---|
| Language | Ruby 3.3 | matches Jorge's other Rails 8 apps; 3.4 when the gems catch up |
| Framework | Rails 8.1 | `load_defaults 8.1`; Solid* adapters remove Redis; built-in auth generator |
| Database | PostgreSQL 17 | one database for app data, queue, cache and cable |
| Server | Puma + Thruster | Rails default; Thruster gives HTTP/2, asset caching, X-Sendfile |
| Hosting (Phase 1) | Fly.io or Render, single region, Kamal-ready Dockerfile | cheapest path to a MainNet URL with TLS |
| Sidecar | Node 22 + TypeScript | the MCP SDK is TypeScript-first |

## Gems

### Application

| Gem | Why this one | Notes |
|---|---|---|
| `pg`, `puma`, `propshaft`, `importmap-rails`, `turbo-rails`, `stimulus-rails` | Rails 8 defaults | no JS bundler, no node_modules in `gateway/` |
| `solid_queue`, `solid_cache`, `solid_cable` | background jobs, cache, websockets on Postgres | no Redis to run or pay for |
| `tailwindcss-rails ~> 4` | Tailwind v4 through the standalone binary | daisyUI is vendored as `.mjs` so no npm is needed |
| `view_component` | components with Ruby classes, testable with `render_inline` | replaces partials entirely |
| `rails_icons` | Lucide SVGs inlined at render time | icons follow `currentColor`, no icon font |
| `faraday` + `faraday-retry` | one HTTP client for the facilitator and for proxying upstream | timeouts per endpoint; retries only on idempotent facilitator reads |
| `rack-attack` | throttle unpaid probes and per-IP bursts on `/s/*` | Phase 1 |
| `rouge` | syntax highlighting rendered on the server | no JS highlighter, works in both themes via CSS vars |
| `pagy` | pagination for calls / ledger tables | lighter than Kaminari |
| `mission_control-jobs` | UI for Solid Queue | mounted behind auth |
| `bootsnap`, `thruster`, `tzinfo-data` | Rails defaults | — |

### Development / test

| Gem | Why |
|---|---|
| `lookbook` | every ViewComponent preview browsable at `/lookbook`, switchable to the dark theme |
| `debug`, `web-console` | Rails defaults |
| `brakeman`, `rubocop-rails-omakase` | security scan and the Rails-blessed style, unchanged |
| `webmock` | stub facilitator and upstream HTTP in unit tests |
| `capybara`, `selenium-webdriver` | system tests, run as a separate CI job |

### Deliberately not used

| Not used | Instead | Why |
|---|---|---|
| Devise | Rails 8 `generate authentication` | one model, sessions, bcrypt; enough for sellers |
| RSpec / FactoryBot | Minitest + fixtures | zero config, fast, one fewer DSL (ADR 0005) |
| Sidekiq / Redis | Solid Queue | one datastore |
| esbuild / webpack / Vite | importmap | no build step for JS |
| Flowbite / Preline / shadcn ports / any second component library | daisyUI + ViewComponent | two class systems fight over Tailwind (ADR 0003) |
| Alpine / React / Stimulus add-ons | plain Stimulus | three small controllers cover the UI |
| Chart libraries | none yet | earnings chart in Phase 2 → decide then (likely inline SVG in a component) |
| An Algorand Ruby SDK | the facilitator's HTTP API | the gateway never signs transactions; it only builds requirements and calls `/verify` + `/settle` |
| dry-rb, interactor gems | our own 30-line `Result` | the contract is small enough to own |

## Front-end assets

| Asset | Source | License |
|---|---|---|
| daisyUI 5.x | `app/assets/tailwind/daisyui.mjs`, `daisyui-theme.mjs` from the GitHub release | MIT |
| Geist, Geist Mono | `public/fonts/*.woff2` from `vercel/geist-font` | SIL OFL 1.1 (license file next to them) |
| Lucide icons | downloaded by `rails_icons:install` into `app/assets/svg/icons/lucide` | ISC |

Upgrade path: re-download the two daisyUI files and bump the note at the top of `application.css`; nothing else changes.

## mcp-hub (Phase 1)

| Package | Why |
|---|---|
| `@modelcontextprotocol/sdk` | official MCP server SDK |
| `zod` | tool input schemas, generated from the gateway's catalog JSON |
| an x402 client library for Algorand (GoPlausible's TypeScript packages) | pays from the agent's configured wallet |
| `tsx`, `vitest` | run and test without a build step |
