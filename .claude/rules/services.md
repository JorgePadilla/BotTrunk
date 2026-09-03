---
paths:
  - "gateway/app/services/**"
  - "gateway/app/controllers/**"
  - "gateway/app/models/**"
  - "gateway/app/jobs/**"
---
# Services, controllers, models

- Service: `app/services/<domain>/<verb>_<noun>.rb` → `Domain::VerbNoun`. Keyword-arg `initialize`, one public `call`, returns `Result.success(data)` or `Result.failure(error, code:)`. Never raise for expected failures. Never render or read request headers (except `payments/`).
- A service over ~80 lines gets split. Services compose services; jobs and middleware only orchestrate.
- Controller: parse params → one service → render/redirect. No business branching beyond `result.success?`.
- Model: validations, scopes, associations. No callbacks that touch other models or external systems.
- Jobs are thin wrappers around a service (`SettlePaymentJob` → `Payments::SettlePayment`).
