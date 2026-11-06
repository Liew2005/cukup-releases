# Setup

## Requirements

- Flutter (stable) and the Android SDK
- Node.js 20+
- A free Cloudflare account
- A free Gemini API key (for receipt parsing; the app still reads receipts offline without it)
- For OTA releases: the GitHub CLI (`gh`) signed in, and a public GitHub repo to hold APKs

## 1. Backend

```bash
cd worker
npm install
npx wrangler login
npx wrangler d1 create cukup
```

Copy the printed `database_id` into `worker/wrangler.toml`, replacing `REPLACE_WITH_YOUR_D1_DATABASE_ID`. Then create the schema and seed data:

```bash
npx wrangler d1 migrations apply cukup --remote
```

Set the secrets:

```bash
node scripts/hash-password.mjs "a password of 10+ characters"
npx wrangler secret put APP_PASSWORD_HASH     # paste the printed hash
npx wrangler secret put JWT_SECRET            # any long random string
npx wrangler secret put GEMINI_API_KEY
npx wrangler deploy
```

`wrangler deploy` prints your Worker URL.

### Optional: two-factor login

```bash
node scripts/setup-2fa.mjs          # shows a secret to add to an authenticator app
node scripts/setup-2fa.mjs --off    # turn it off again
```

### Rotating the password and signing key

```bash
node scripts/rotate-secrets.mjs
```

### Local development

Create `worker/.dev.vars` (git-ignored) with `APP_PASSWORD_HASH`, `JWT_SECRET` and optionally `GEMINI_API_KEY`, then run `npm run dev`.

## 2. App

1. In `app/lib/core/config.dart` set `apiBase` to your Worker URL, `defaultPayLink` to your payment link, and `updateFeed` to your releases repo (or empty to turn update checks off).
2. Replace `app/assets/tng_qr.png` with your own payment QR (used in friend payment reminders).
3. Run:

```bash
cd app
flutter pub get
flutter run
```

If you change the Drift schema, regenerate code with `dart run build_runner build`.

### Signing a release build

Create a keystore and `app/android/key.properties` (both git-ignored):

```
storePassword=...
keyPassword=...
keyAlias=...
storeFile=../cukup-release.jks
```

Back the keystore up. If it is lost, installed copies can no longer be updated in place.

## 3. Shipping an update

```powershell
.\scripts\release.ps1 -Repo your-name/your-releases-repo -Notes "What changed"
```

The script bumps the build number, builds a signed arm64 APK, and creates a GitHub release containing the APK and `version.json`. Installed apps offer the update from Settings.

## Tests

```bash
cd app && flutter analyze && flutter test
cd worker && npm run typecheck && node scripts/receipt.test.mjs
```

`worker/scripts/smoke.test.mjs` and `parse.test.mjs` are integration tests that run against `wrangler dev`; the header of each file explains how to start it.
