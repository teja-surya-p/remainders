# Data safety form (draft answers)

Play Console → Policy → App content → Data safety. Answers describe v1 as
built (paywall, analytics and sharing switched off; RevenueCat not started).
Re-check them whenever a feature flag is turned on.

**Does your app collect or share any of the required user data types?** Yes.

**Is all of the user data collected by your app encrypted in transit?** Yes
(Firebase uses HTTPS).

**Do you provide a way for users to request that their data be deleted?**
Yes: in the app (Profile → Delete account) and on the web
(delete-account page).

**Shared with third parties?** No. Google (Firebase) processes data on our
behalf as a service provider, which Play doesn't count as sharing.

## Data types collected

| Category | Type | Required or optional | Purpose |
|---|---|---|---|
| Personal info | Email address | Optional (only when signing in) | Account management |
| Personal info | Name | Optional (sign-up name, or from Google) | Account management |
| Personal info | User IDs | Optional (account ID when signing in) | Account management, App functionality |
| App activity | Other user-generated content (reminders and their history, in the backup) | Optional (only when signed in) | App functionality |
| App info and performance | Crash logs | Required | App functionality (fixing crashes) |
| App info and performance | Diagnostics (device model, OS and app version in crash reports) | Required | App functionality |
| Device or other IDs | Crashlytics installation ID | Required | App functionality |

None of it is used for advertising or sold. Reminders that stay on the
phone (signed out) are not "collected": they never leave the device.

**Not collected**: location, financial info, health and fitness (reminder
text is user-generated content), messages, photos, audio, files, calendar,
contacts, web browsing, installed apps.
