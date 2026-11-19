# Project brief

A one-page view of Cukup from the product and delivery side: what problem it solves, what is in and out of scope, the decisions made along the way, and how quality is checked. The technical detail lives in [ARCHITECTURE.md](ARCHITECTURE.md).

## Problem and goal

Most expense trackers want a subscription, a bank login, or both, and they answer "what did I spend?" rather than "am I okay this week?".

**Goal:** a free, private app that answers one question, *"Am I still within what I decided is enough this week?"*, with as little typing as possible.

**Success looks like:** it is used daily, a receipt goes from photo to saved entry in under a minute, and it costs RM 0 to run.

## Users

- **Primary:** one daily user (the author) who pays for most things by e-wallet, card and cash in Malaysia.
- **Secondary:** friends who split bills with that user and pay them back later.

## Constraints

| Constraint | Effect on the design |
|---|---|
| Whole stack must be free | Cloudflare Workers and D1 free tier, Gemini free-tier API, GitHub Releases for distribution |
| No bank logins | Spending is captured from receipts, payment notifications and shared screenshots instead |
| Android only, no Play Store | Sideloaded APK with an in-app updater that reads a public release feed |
| Must work with poor signal | Offline-first app; an offline receipt parser takes over when the server cannot be reached |
| Personal finance data | Optional two-factor login, app lock, allowlisted notification sources, nothing sensitive in the public repo |

## Scope

| In scope | Out of scope (for now) |
|---|---|
| Receipt scan with item-level review | iOS |
| Weekly cap with carry-over | Play Store release |
| Split bills and a friends ledger | Bank or card account linking |
| Payment detection, screenshot import, quick add | Multi-user accounts |
| Bills, recurring entries, savings sweep | Paid features of any kind |
| Insights, month in review, CSV export | |

## Releases

| Stage | What it added |
|---|---|
| v1 | Receipt scanning and auto-categorising, item splitting with friends' items left out, income tracking, share-sheet screenshot import, week-end leftover sweep to savings, duplicate warning |
| Later | Fingerprint app lock, optional authenticator-app 2FA, friends and bill splitting with a payment ledger, custom categories, home-screen widget and Quick Settings tile |
| v10 | Instant save from the payment banner, search and filters in Activity, Month in review, sync for phone-only data |
| Next | Gmail receipts (read-only, on-device). Details in [ROADMAP.md](ROADMAP.md) |

## Key decisions

| Decision | Why | Trade-off accepted |
|---|---|---|
| Gemini free tier for receipt reading | The Claude and Google AI student plans do not include API use, and the stack had to stay free | Rate limits and regional blocks, handled with an offline fallback and a Worker pinned near Singapore |
| Do not trust model output | A wrong total is worse than a slow one | Extra reconciliation step that flags a mismatch instead of silently fixing it |
| Overspending carries into next week, at most 50% of the base cap; underspending does not carry | Keeps the cap meaningful without punishing one bad week forever | Saved money goes to the savings sweep instead of widening the next cap |
| Money stored as integer sen | Avoids floating-point drift | Conversion at the edges |
| Carry-over derived from entries, not stored | Editing an old entry corrects every later week | Recomputed on read |
| Optional 2FA, short password allowed | Daily-use friction matters on a personal app | Second factor is opt-in |
| Sideload plus OTA updates | No store review, instant releases | Users must allow installs from the browser |

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| AI misreads a receipt | Reconciliation step, quantity-aware review screen, total-mismatch warning |
| Server or AI unavailable | On-device OCR and a rule-based parser for English, Malay and Chinese receipts |
| Same purchase reported twice (for example by two payment apps) | Merge window plus a duplicate warning |
| Secrets or personal data reach the public repo | Export script swaps personal values for placeholders and scans for leaks before any push |
| A release breaks something | Fixed verification checklist per release (below) |

## Quality approach

- Pure logic (splits, carry-over, parsing, recurring schedules, updater) is plain Dart with unit tests: 129 Flutter tests, 9 Kotlin tests for payment detection, and worker suites for receipt reconciliation and parsing.
- Every release runs the checklist in [ROADMAP.md](ROADMAP.md#verification-for-every-release): static analysis, unit tests, a debug build, worker type-check and smoke tests, a leak scan of the public copy, then a manual check on a real phone.

## Role

Sole owner: requirements, design, development, testing, release and documentation.

## What I would do next

1. Add CI so tests run on every push.
2. Replace prototype screenshots with real ones.
3. Ship Gmail receipts.
4. Add a credit card view (what is owed and when the statement is due).
