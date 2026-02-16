# Android Google Sign-In Fix (`ApiException: 10`)

This error means Google OAuth is not configured for the signing certificate currently used by the app.

## App package
`com.suryatejap24.snooze`

## SHA-1 fingerprints to add in Firebase
Add these in Firebase Console:
Project Settings -> Your apps -> Android (`com.suryatejap24.snooze`) -> Add fingerprint

- Debug SHA-1: `CF:13:8F:27:79:50:CE:81:9A:AD:A2:19:E6:62:FB:4A:72:CF:00:AB`
- Upload/Release SHA-1: `A3:2E:14:A9:6D:09:96:EB:F5:D5:34:E0:63:C0:6E:91:02:2E:DE:ED`
- If testing from Play Internal/Closed track: also add **Play App Signing** SHA-1 from Play Console -> App Integrity

## After adding fingerprints
1. Download the updated `google-services.json` from Firebase.
2. Replace `/android/app/google-services.json`.
3. Rebuild:
   - `flutter clean`
   - `flutter pub get`
   - `flutter run`

## Notes
- Current `google-services.json` in this repo includes the debug certificate hash.
- Release-signed builds require the release (upload or Play signing) SHA-1 to be registered.
