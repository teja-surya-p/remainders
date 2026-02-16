# snooze_app

A Flutter reminder app with RevenueCat subscriptions.

## RevenueCat live key setup (required for real purchases)

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
