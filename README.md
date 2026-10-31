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
