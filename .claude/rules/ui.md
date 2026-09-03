---
paths:
  - "gateway/app/components/**"
  - "gateway/app/views/**"
  - "gateway/app/assets/**"
  - "gateway/app/javascript/**"
  - "gateway/test/components/previews/**"
---
# UI

- Every reusable element is a ViewComponent under `app/components/<namespace>/`, subclassing `ApplicationComponent`, keyword args only, one preview in `test/components/previews/`. No shared ERB partials.
- Style with daisyUI + Tailwind classes only. The only custom utilities are `text-muted` and `hairline` in `app/assets/tailwind/application.css`; add a new one only when three components need it.
- Two themes, monochrome: `bottrunk-light` (default) and `bottrunk-dark`. No brand accent. `text-success` only for paid/settled/verified, `text-error` for failures, `info` only inside code.
- Look: clean and spacious — big headline, hairline borders, generous padding, one fact per line. When in doubt, remove something. No gradients, illustrations, emoji or stat pile-ups.
- Type: Geist (UI), `font-mono` for prices, endpoints, ids, code. Icons: Lucide via `icon("name", class: "size-4")`, stroke 1.75, never emoji.
- JS: Stimulus only (`theme`, `clipboard`, `tabs` exist). No other framework or library.
- The mockups are the spec: "BotTrunk Catalog" design canvas. Components mirror them 1:1.
