# Architecture

Cukup is a two-part system: an offline-first Flutter app and a small serverless API. Everything runs on free tiers.

## Components

```mermaid
flowchart TB
    subgraph App["Flutter app"]
        direction TB
        F["features/ (screens)"]
        P["data/providers.dart (Riverpod)"]
        C["core/ (pure Dart logic)"]
        D["data/ (Drift DB, API, OCR, sync)"]
        F --> P --> D
        P --> C
    end
    subgraph Worker["Cloudflare Worker (Hono)"]
        R["routes/"]
        A["auth + TOTP"]
        RC["receipt.ts (reconcile)"]
        R --> A
        R --> RC
    end
    D1[("D1")]
    D <--> R
    R --> D1
```

| Layer | Responsibility |
|---|---|
| `core/` | Pure Dart: money formatting, bill splitting, friends ledger, weekly carry-over, duplicate detection, recurring schedule, screenshot parser, CSV, update parsing. No Flutter imports, so it is fast to unit test. |
| `data/` | Drift database, API client, sync, ML Kit OCR, offline receipt parser, notifications, widget sync, OTA updater. |
| `features/` | One file per screen or reusable widget. |
| Worker | Auth, CRUD and sync endpoints, receipt parsing, CSV export, ledger storage. |

## Data model

```mermaid
erDiagram
    categories ||--o{ transactions : classifies
    transactions ||--o{ transaction_items : contains
    categories ||--o{ merchant_rules : learned
    categories ||--o{ recurring : classifies
    goals ||--o{ sweeps : receives

    transactions {
        text id PK "client UUID"
        text spent_at "YYYY-MM-DD"
        int amount_cents "my share"
        int receipt_total_cents "full bill"
        int tax_cents
        text payment_type
        int counts_toward_cap
        text deleted_at "soft delete"
    }
    transaction_items {
        text id PK
        text name
        int price_cents
        int included
    }
```

Design choices:

- **Integer cents everywhere.** `RM 12.50` is `1250`. No floating point touches money.
- **Client-generated UUIDs** mean a retried sync can never create duplicates.
- **Soft deletes** (`deleted_at`) let deletions propagate to other devices.
- **ISO 8601 UTC timestamps** compare correctly as strings, which keeps "newer wins" logic simple.
- **Dates are plain `YYYY-MM-DD` in Malaysia time (UTC+8)**, so a late-night entry lands on the day the user means.

## Sync

The phone writes first and syncs when it can: push local changes, then pull anything newer (`updated_since`). Entries merge by `updated_at`. The friends ledger is a single JSON document stored in its own table; the phone is the only writer, so the newest copy wins. A local dirty flag decides whether to push, and an older server that lacks the endpoint is tolerated.

## Receipt pipeline

```mermaid
flowchart LR
    A["Photo"] --> B["ML Kit OCR<br/>on device"]
    B --> C{"Server<br/>reachable?"}
    C -- yes --> D["Worker: Gemini<br/>JSON schema output"]
    D --> E["reconcile()"]
    C -- no --> F["Offline rule parser<br/>EN / MS / ZH"]
    E --> G["Review screen"]
    F --> G
```

1. The image is turned into text on the phone, so the photo itself never has to leave the device.
2. The text goes to the Worker, which asks Gemini for structured output against a JSON schema (items with quantity and unit price, service charge, SST, total).
3. `reconcile()` in `worker/src/receipt.ts` enforces the arithmetic: quantity x unit price must match the line total, and tax and service are copied only when printed.
4. If the server is unreachable or fails, the on-device parser takes over with a deliberately cautious confidence score, so uncertain fields are highlighted for the user to check.

Malaysia has two common charges, a 6% SST and a 10% service charge, and shops differ in which they apply. The pipeline reads what is printed and never calculates tax itself. The review screen warns if items plus charges do not match the receipt total.

## Payment detection

```mermaid
flowchart LR
    N["Notification from a<br/>wallet or bank app"] --> L["PaymentListener<br/>(Android service)"]
    L --> D{"PaymentDetect:<br/>money going out?"}
    D -- no --> S["Logged as skipped<br/>(numbers masked)"]
    D -- yes --> F[("detected.jsonl<br/>app-private file")]
    F --> P["Heads-up banner:<br/>Save / Delete"]
    P --> F
    F --> A["Flutter: Home card,<br/>saves entries"]
```

The listener is a native `NotificationListenerService`, so it works while the Flutter app is closed. It only looks at an allowlist of apps, matched by package name or app label. `PaymentDetect.kt` holds every rule as pure Kotlin with no Android classes: is the text money going out, how much, which shop, which card. It is the only copy of those rules and is covered by JUnit tests that run on the computer (`gradlew :app:testDebugUnitTest`), including real notification wording such as a Google Wallet tap.

The service and the app communicate through files in the app's private storage, each with exactly one writer, so no locking is needed. The service appends to `detected.jsonl`: detections, merges (a second app reporting the same amount within 30 minutes) and the Save / Delete taps. Flutter only reads it and keeps its own list of handled ids. In the other direction Flutter writes `detect_ctx.json` (category names, learned shop rules, remembered card types) so the banner can show a category and payment type while the app is closed. When the app next opens or resumes it turns every "Save" into an entry with a fixed id (`det-<id>`), which makes saving idempotent. Nothing is ever saved without an explicit Save.

Tapping the banner starts the app with the detection id, which opens a Confirm sheet (a transparent route over whatever screen was showing) for editing before saving.

**Saving while the app is closed.** The banner's Save button records the tap, then starts a headless Flutter engine through the home-screen widget package's background receiver and WorkManager. The Dart entry point (`lib/data/background.dart`) builds a Riverpod container and runs the same controller the app uses: create the entry, update the widget, refresh reminders, and wait for a sync. It opens its own database connection, so when the app returns to the foreground it marks the entry tables as changed to refresh its lists. Because entries have fixed ids, the background run and the open app can both try to save and still produce one entry.

## App state sync

Small settings-like records (savings goal and sweeps, shop-to-category rules, remembered cards, reminder switches, pay link) are local key-value rows. They sync as one document, `{ "v": 1, "kv": {...} }`. The phone remembers the document as it stood after the last sync, which lets a pure function (`core/app_state.dart`, unit tested) decide the merge: if nothing changed locally, take the server copy; if something did, keep both and let the phone win conflicts. These values are only ever added or changed, never removed, so the union loses nothing. Only an allowlist of keys travels, in both directions, so a bad document cannot touch unrelated settings.

## Categories

Categories are owned by the server and replaced wholesale on each pull, so the phone never has to merge them. Each carries `cap_default`, which sets the starting position of the "counts toward weekly cap" switch for new entries. Deleting a category reassigns its entries, repeating items and shop rules to a fixed fallback ("Other" or "Other income") in one batch and bumps `updated_at`, so the change reaches every device through the normal sync.

## Split maths

A bill becomes a list of slots, one per unit ordered. Each slot records who had it; several people on one slot share it evenly, and a slot can be marked as a treat.

1. Each person's subtotal is the sum of their slots.
2. Tax, service charge and rounding are spread in proportion to those subtotals using **largest-remainder allocation**, so the shares add up to the receipt total to the sen.
3. Slots nobody is tracking take their share of tax but are charged to nobody.
4. A treat puts the slot on the payer, so it counts toward their weekly spending.
5. Odd sen go to the payer.

Only the payer's own share is saved as the transaction amount and counts toward the weekly cap. Each friend's share becomes a debt linked to the transaction id, so editing the receipt replaces its debts and deleting it removes them.

## Weekly cap and carry-over

Overspending in a week becomes debt that later weeks repay, taking at most a fixed share of the base cap each week. Underspending is never added to a later week; leftover money goes to the optional savings sweep instead. The available cap is derived from entries on demand, so edits to past entries correct everything after them.

## Notifications and widget

Reminders (bills, daily nudge, weekly summary, cap alerts) are scheduled locally, so they work offline and cost nothing. The home-screen widget is updated whenever the cap or this week's spend changes.

## Over-the-air updates

`scripts/release.ps1` bumps the build number, builds a signed arm64 release APK, and publishes it with a small `version.json` to a public GitHub releases repo. The app reads that file once per launch, compares build numbers, and hands the downloaded APK to the Android installer through a `FileProvider`.
