# ADR 0001 — Rails 8.1 monolith on PostgreSQL

**Status:** accepted · **Date:** 2026-09-02

## Context
Solo developer, 5–10 hrs/week, deep Rails experience, a five-week hackathon window, and a product whose core is HTTP request handling plus a ledger.

## Decision
One Rails 8.1 application (`gateway`) with PostgreSQL as the only datastore: Solid Queue for jobs, Solid Cache for caching, Solid Cable for websockets. Hotwire for the UI. Propshaft + importmap, no JS bundler. Kamal-ready Dockerfile; deploy target Fly.io/Render.

## Consequences
- One process type to run and one thing to back up.
- No Redis, no Node in the Rails app.
- The MCP hub is the only non-Ruby code (ADR 0007).
- When traffic justifies it, Solid Queue can move to its own database without code changes.
