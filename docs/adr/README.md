# Architecture Decision Records

One file per decision. Format: Context → Decision → Consequences. Status is `accepted` unless superseded; never edit an accepted ADR — write a new one that supersedes it.

| # | Decision |
|---|---|
| [0001](0001-rails-monolith-postgres.md) | Rails 8.1 monolith on PostgreSQL with Solid Queue/Cache/Cable |
| [0002](0002-service-objects-result.md) | Business logic in service objects returning `Result` |
| [0003](0003-ui-stack.md) | ViewComponent + Tailwind v4 + daisyUI v5, monochrome two-theme design, no other UI libraries |
| [0004](0004-x402-algorand-facilitator.md) | Payments over x402 on Algorand via the GoPlausible facilitator, behind an adapter |
| [0005](0005-minitest.md) | Minitest and fixtures |
| [0006](0006-money-as-integers.md) | Money stored as integer atomic units |
| [0007](0007-mcp-hub-sidecar.md) | The MCP hub is a stateless TypeScript sidecar |
