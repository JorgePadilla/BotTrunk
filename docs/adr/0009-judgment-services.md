# ADR 0009 — Judgment services use a hosted judge model, with questions we write

**Status:** accepted · **Date:** 2026-10-17

## Context
BotTrunk sells agents raw web data: scraping, metadata, links, health. What a crawling or acting agent still lacks is a cheap *judgment* about that data. Is this page a login wall or a soft 404? Does it answer my question? Is this text trying to hijack me? Should I run this command? Rules and regexes can't make those calls, and a general LLM would cost too much and be too slow behind a 2-cent endpoint.

A class of hosted "judge" models does exactly this job. You send a state and typed questions (yes/no, a choice over options, or a score on a scale you describe), and you get back typed answers with probabilities. They never generate text, cost fractions of a cent a call, and answer in about 100 ms.

The provider's customer agreement allows its API inside applications we build and operate for our own users, and it assigns us the rights to the outputs. It forbids:
- offering the model as a standalone service, including a pass-through where buyers send their own questions;
- sharing the key;
- training anything on the answers;
- using the provider's name or brand.

## Decision
- **Built-in fulfillers** (`injection-check`, `page-kind`, `tool-call-gate`, `page-fit`) call one client, `Judgment::Judge`. The provider, endpoint, model and key are configuration (`JUDGE_API_URL`, `JUDGE_MODEL`, `JUDGE_API_KEY`), not code.
- **BotTrunk writes every question.** They live in `Judgment::Rubrics`, along with the thresholds and the code deny rules. Buyers send only the data the questions are about. We never list a service that takes buyer-written questions or labels and returns raw answers to them.
- **Responses never name the provider or the model.** They carry `Rubrics::VERSION`, which changes whenever a question or threshold changes. Listings say only that input is sent to a third-party model provider that does not train on requests.
- **Verdicts are advisory.** Exact rules (the gate's `DENY` list) run in code before the judge, and nothing it answers can loosen them. Buyer input always goes into its own named field in the state.
- **No training.** Judge answers are never stored for training or distillation.

## Consequences
- These are near-100% margin services that reuse the existing fetch pipeline (`Fulfillers::ScrapeMarkdown`), so the SSRF guard and size limits come for free.
- The provider can be swapped by changing configuration plus the one wire-format constant in `Judgment::Judge`.
- Without configuration, every judgment service answers 502 `judging is not configured` and nothing is charged, the same as rendering without Cloudflare credentials.
- The judge's rate limit is shared with any other use of the same key. Rack::Attack in front of `/s/*` is the first line of defence.
- Adding a "bring your own question" service needs a separate signed agreement with the provider first.
