# Cukup app

The Flutter Android client for [Cukup](../README.md). It is offline-first: everything is stored on the phone in SQLite (Drift), and the Cloudflare Worker in `../worker` only adds receipt parsing and sync between devices.

## Layout

| Folder | Contents |
|---|---|
| `lib/core/` | Pure Dart logic (splits, ledger, carry-over, parsing, CSV). No Flutter imports. |
| `lib/data/` | Database, API client, sync, OCR, notifications, widget sync, OTA updater |
| `lib/features/` | Screens and reusable widgets |
| `lib/theme/` | Colours, type and spacing |
| `android/` | Kotlin side: payment notification listener, home-screen widget, Quick Settings tile, installer provider |
| `test/` | Unit tests |

## Run it

```bash
flutter pub get
# set apiBase in lib/core/config.dart to your own Worker URL
flutter run
```

## Check it

```bash
flutter analyze
flutter test
cd android && ./gradlew :app:testDebugUnitTest
```

Full setup, signing and release steps: [../docs/SETUP.md](../docs/SETUP.md).
