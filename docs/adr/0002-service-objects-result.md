# ADR 0002 — Service objects returning `Result`

**Status:** accepted · **Date:** 2026-09-02

## Context
The paid-call flow has six steps with external calls in the middle. Putting it in controllers or model callbacks makes it untestable without HTTP and impossible to run from a job or the MCP hub.

## Decision
Every business action is a class under `app/services/<domain>/`, named `Domain::VerbNoun`, with keyword-argument `initialize`, one public `call`, and a `Result` return value (`Result.success(data)` / `Result.failure(error, code:)`). Expected failures are results, not exceptions. Controllers, jobs and middleware only orchestrate services. We write our own ~30-line `Result` instead of pulling dry-rb or an interactor gem.

## Consequences
- The whole payment loop is unit-testable with a fake adapter.
- Services compose: `SettlePayment` can be called inline (Phase 0) or from a job (Phase 1) unchanged.
- Discipline required: a service that grows past ~80 lines is split.
