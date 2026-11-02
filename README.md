# Snooze

Reminders for things you can't miss — medicines, deadlines, appointments.
Snooze rings like an alarm at the exact minute, keeps ringing until you snooze
or dismiss it, and keeps working offline, after reboots, and with the app closed.

Android first (iOS later). Built with Flutter.

## Development

Requirements:
- Flutter **3.38.9** (stable), Dart 3.10
- **Java 17** for Android builds. If your default JDK is newer (Gradle 8.14
  supports up to Java 24), set it per shell:
  ```bash
  export JAVA_HOME=$(/usr/libexec/java_home -v 17)
  ```

Run every check CI runs (format, analyze, tests in three time zones):
```bash
tool/check.sh
```

Run on an emulator or a connected phone:
```bash
flutter run
```

Build a debug APK:
```bash
flutter build apk --debug
```

CI (`.github/workflows/ci.yml`) runs `tool/check.sh` and a debug app-bundle
build on every push to `main` and `v1/**` branches and on pull requests.

## How it's organised

- `lib/storage/`: the device database (SQLite, the source of truth) and the
  optional Firestore backup (`reminder_backup.dart`).
- `lib/scheduling/` and `lib/reminder_scheduler.dart`: plans each reminder's
  alarms and keeps Android's pending list in step; `lib/background/`
  re-arms after reboot, update and time changes.
- `lib/reminders/`: recurrence, suggestions; `lib/reminder_service.dart`:
  reminder actions (create, snooze, complete, miss).
- `lib/reliability/`, `lib/onboarding/`: the "make sure alarms ring" check.
- `lib/account/`: sign-in, sign-out, account deletion; `lib/legal/`: the
  privacy policy and terms (also exported to `docs/`).

## Feature flags

Built but off in v1 (`lib/features.dart`); turn one on per build with
`--dart-define`:

| Flag | What it switches on |
|---|---|
| `SNOOZE_PAYWALL=true` | Purchases (RevenueCat), the Pro tab and Pro-only limits |
| `SNOOZE_ANALYTICS=true` | The Analytics tab (insights, streaks, leaderboard) |
| `SNOOZE_SHARING=true` | Shared reminders and invites |
| `SNOOZE_DEV_TOOLS=true` | The Test alarm button (debug builds only) |

Turning on the paywall or sharing also needs the privacy policy and the
Play Data safety answers (`store/data-safety.md`) updated.

## Release

1. Put the upload key's details in `android/key.properties` (never
   committed):
   ```properties
   storeFile=/absolute/path/to/upload-keystore.jks
   storePassword=...
   keyAlias=...
   keyPassword=...
   ```
   Release builds stop with an error if this file is missing; they never
   fall back to the debug key.
2. Raise `version:` in `pubspec.yaml` (the number after `+` must go up for
   every Play upload).
3. Build the bundle and upload it to Play Console:
   ```bash
   flutter build appbundle --release
   ```

Store art and listing text live in `store/`. To redraw the launcher icon,
store icon and feature graphic (needs Pillow):
```bash
python3 tool/make_icons.py "$(dirname "$(dirname "$(which flutter)")")"
```
The privacy policy, terms and account-deletion pages are generated from
`lib/legal/legal_texts.dart`; after editing the texts run
`dart run tool/export_legal.dart` and commit `docs/`. GitHub Pages serves
them from `main` → `/docs`.

## RevenueCat live key setup (paywall; off in v1)

1. Copy key template:
```bash
cp revenuecat.keys.local.json.example revenuecat.keys.local.json
```
2. Edit `revenuecat.keys.local.json` and set:
- `RC_ANDROID_PUBLIC_KEY` to your RevenueCat Android public SDK key (`goog_...`)
- `RC_IOS_PUBLIC_KEY` to your RevenueCat iOS public SDK key (`appl_...`)

3. Run Android with live keys:
```bash
./scripts/run_android_live.sh
```

4. Build Android AAB with live keys:
```bash
./scripts/build_android_live_aab.sh
```

`revenuecat.keys.local.json` is gitignored and should never be committed.
