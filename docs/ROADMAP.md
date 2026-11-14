# Roadmap

## Done in v10

- **Instant save from the banner.** Save runs the app's own code in the background: entry, widget, cap alert and sync, without opening the app.
- **Search and filters in Activity.** Period, payment type, "outside the weekly cap", and a total for whatever is shown.
- **Month in review.** A summary screen per month and a reminder on the 1st.
- **Sync for phone-only data.** Savings goal and sweeps, shop rules, remembered cards, reminder switches and the pay link.

## Next: Gmail receipts (needs a one-time Google setup)

- **Connect Gmail** in Settings > Detect payments, using Google's own authorization for the read-only Gmail scope. Cukup never sees a password.
- **Trigger.** A Gmail notification that looks like a receipt makes the phone fetch that one email through the Gmail API and read sender, subject and body.
- **Rules** (Kotlin, unit tested): receipt wording plus an RM/MYR amount, preferring a labelled total. Shop is the sender. Promotions, statements and "payment due" emails are skipped.
- **Catch-up.** Opening the app scans the last two days.
- **Privacy.** Read-only access; the token and email text never leave the phone; the log keeps sender and subject only; message ids already read are remembered.
- Email detections use the same merge (3-hour window) and the same banner as every other source.

**Files.** new `GmailReader.kt`, `PaymentDetect.kt` (+ tests), `PaymentListener.kt`, `MainActivity.kt`, `android/app/build.gradle.kts` (Google Identity dependency), `lib/features/detected_card.dart`.

## Ideas, not yet planned

- A credit card view: what is owed on each card and when the statement is due.
- Soft budgets per category inside the weekly cap.
- Real screenshots in the README and a CI workflow that runs the tests on every push.

## Verification for every release

1. `flutter analyze`, `flutter test`.
2. `gradlew :app:testDebugUnitTest` for the Kotlin rules.
3. `flutter build apk --debug` to prove the Android side compiles.
4. Worker: `npm run typecheck`, `node scripts/receipt.test.mjs`, smoke tests against `wrangler dev` with new migrations applied locally.
5. Public copy: `scripts/export-public.ps1` scan passes before any push.
6. On the phone: the checklist in the release notes, then the Detect payments log for tuning.
