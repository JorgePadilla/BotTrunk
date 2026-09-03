# ADR 0003 — ViewComponent + Tailwind v4 + daisyUI v5, monochrome, nothing else

**Status:** accepted · **Date:** 2026-09-02 (supersedes the amber/dark first draft of the same day)

## Context
The site must look credible to agent developers and clean to non-technical sellers, with almost no design time. First draft (amber accent on blue-black, dense stat cards) was rejected: too much color, too much information. Reference for tone: vercel.com.

## Decision
- Every reusable UI element is a ViewComponent with a Lookbook preview.
- Styling only with Tailwind v4 utilities and daisyUI v5 components; daisyUI is vendored as a standalone `.mjs` plugin so the Rails app needs no npm.
- Two custom daisyUI themes, `bottrunk-light` (default) and `bottrunk-dark`, both monochrome. No brand accent; `success` green only for paid/settled/verified, `error` red for failures, `info` only inside code.
- Typography: Geist and Geist Mono, self-hosted. Icons: Lucide via rails_icons.
- Layout rules: big headline, hairline borders, generous padding, one fact per line. When in doubt, remove.
- Interactions with plain Stimulus. No second component library, no Alpine/React, no icon fonts.

## Consequences
- The design system is ~150 lines of CSS plus components; a newcomer can hold it in their head.
- Anything daisyUI lacks (command palette, charts) is built as a component, not imported.
- Mockups live in the "BotTrunk Catalog" design canvas; the components mirror them 1:1.
