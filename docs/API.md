# API reference

A single-user JSON API served by a Cloudflare Worker. Amounts are integer cents. Dates are `YYYY-MM-DD` (Malaysia time) and timestamps are ISO 8601 UTC.

All routes except `/health` and `/auth/*` need `Authorization: Bearer <token>`.

Errors look like `{ "error": "code", "message": "Human readable text" }`.

## Public

| Method | Path | Description |
|---|---|---|
| GET | `/health` | Liveness check. |
| GET | `/auth/config` | Tells the login screen whether to ask for a two-factor code. |
| POST | `/auth/login` | Body `{ "password": "...", "code": "123456" }` (code only when 2FA is on). Returns `{ token, expires_in }`. |

Login is rate limited to 5 failures per IP per 15 minutes (`429 too_many_attempts`). The error never says whether the password or the code was wrong. Tokens are HS256 JWTs valid for 30 days.

## Transactions

| Method | Path | Description |
|---|---|---|
| GET | `/transactions` | List entries. Filters: `from`, `to` (dates), `direction`, `updated_since` (for sync), `include_deleted`, `limit`. |
| GET | `/transactions/:id` | One entry with its items. |
| PUT | `/transactions/:id` | Create or replace an entry. The id is a client UUID, so the call is idempotent. |
| DELETE | `/transactions/:id` | Soft delete. |

Entry fields: `spent_at`, `merchant`, `amount_cents`, `direction` (`spend`/`income`), `receipt_total_cents`, `tax_cents`, `category_id`, `payment_type` (`cash`, `debit`, `credit_card`, `spaylater`, `ewallet`), `counts_toward_cap`, `note`, `source` (`scan`, `manual`, `quick`, `import`, `recurring`), `reference`, `confidence`, and up to 100 `items` of `{ id, name, price_cents, included }`. Amounts are capped at RM 1,000,000.

## Summaries

| Method | Path | Description |
|---|---|---|
| GET | `/summary/week?date=YYYY-MM-DD` | The week containing the date: cap, spent, left, over-cap amount, days left, even daily pace and a safe per-day figure. |
| GET | `/summary/month?month=YYYY-MM` | Totals for a month. |

## Reference data

| Method | Path | Description |
|---|---|---|
| GET | `/categories` | Spending and income categories. |
| GET, PUT | `/rules`, `/rules/:merchant_key` | Learned merchant to category rules. |
| GET, PUT, DELETE | `/bills`, `/bills/:id` | Bills such as SPayLater. |
| GET, PUT, DELETE | `/recurring`, `/recurring/:id` | Repeating income and spending. |
| GET, PUT | `/settings`, `/settings/:key` | Weekly cap, reminder times and similar settings. |

## Friends ledger

| Method | Path | Description |
|---|---|---|
| GET | `/ledger` | The ledger document and its `updated_at`. `404` if none yet. |
| PUT | `/ledger` | Store the ledger. Validated, limited to 900 KB, last write wins. If the server copy is newer it returns `{ "stored": false, "doc": ..., "updated_at": ... }` so the client can adopt it. |

## Receipts and export

| Method | Path | Description |
|---|---|---|
| POST | `/parse-receipt` | Body `{ "text": "<OCR text>" }`. Returns items (with `qty` and `unit_cents`), `service_cents`, `sst_cents`, `tax_cents`, total, merchant, date and a confidence value. |
| GET | `/export.csv` | All entries as CSV. Cells that start with `=`, `+`, `-` or `@` are prefixed to prevent spreadsheet formula injection. |
