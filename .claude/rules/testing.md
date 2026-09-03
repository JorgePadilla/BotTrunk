---
paths:
  - "gateway/test/**"
---
# Tests

- Minitest with fixtures; no RSpec, no FactoryBot.
- Services: unit tests with a fake payment adapter and WebMock. No real HTTP, ever.
- Components: `ViewComponent::TestCase` + `render_inline`; assert on structure and text, not on class strings unless the class is the behavior.
- Controllers: integration tests. System tests run as a separate CI job.
- Every bug fix adds a failing-then-passing test. Keep fixtures small and named.
