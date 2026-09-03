# ADR 0005 — Minitest and fixtures

**Status:** accepted · **Date:** 2026-09-02

## Context
Test framework choice for a one-person Rails app. Jorge's day-job apps use Minitest.

## Decision
Rails default Minitest with fixtures. `ViewComponent::TestCase` for components, integration tests for controllers, WebMock for HTTP. System tests run as a separate CI job. No RSpec, no FactoryBot.

## Consequences
- Zero configuration, fastest suite, one fewer DSL.
- Fixtures must be kept small and named; large scenario setup goes in test helpers, not YAML.
