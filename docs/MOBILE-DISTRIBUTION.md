# Mobile distribution via Firebase App Distribution

The CI workflow can publish a signed Android APK automatically after every
successful push to `main`.

## One-time GitHub configuration

Create these repository Actions secrets:

- `FIREBASE_APP_DISTRIBUTION_SERVICE_ACCOUNT_JSON`: JSON key for a Google
  service account with the Firebase App Distribution Admin role.
- `ANDROID_DISTRIBUTION_KEYSTORE_BASE64`: the stable Android JKS/keystore,
  base64-encoded as a single value.
- `ANDROID_DISTRIBUTION_KEYSTORE_PASSWORD`
- `ANDROID_DISTRIBUTION_KEY_ALIAS`
- `ANDROID_DISTRIBUTION_KEY_PASSWORD`

Create at least one of these repository Actions variables:

- `FIREBASE_APP_DISTRIBUTION_TESTERS`: comma-separated tester email addresses.
- `FIREBASE_APP_DISTRIBUTION_GROUPS`: comma-separated Firebase App Distribution
  group aliases.

The Firebase Android app used by CI is:

- project: `gestionale-radio`
- app ID: `1:1051055442339:android:f495a6326f7a7465fb7216`
- package: `com.example.gestionale_radio`

## Why stable signing is required

Every APK installed as an update must be signed with the same Android key.
The workflow therefore builds a release APK only when the stable keystore and
all signing secrets are available. It never commits the key to Git.

If the required secrets are not configured, normal CI remains green and the
distribution job reports that publishing was skipped.

## Tester flow

After the first Firebase App Distribution invitation is accepted on the phone,
new releases published from `main` become available through the Firebase tester
experience. Android still requires user confirmation to install an APK update.
