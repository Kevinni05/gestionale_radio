# Mobile customer provisioning

This repository is a reusable enterprise product template. A buyer owns the
Firebase project, Android package identity, signing key, distribution account,
backend domain and CI secrets.

## 1. Create the buyer Firebase project

Create a Firebase / Google Cloud project in the buyer organization. Enable:

- Authentication
- Firestore
- Storage
- Cloud Messaging
- App Check
- App Distribution when used for internal delivery

Register the Android app with the buyer package ID. Then replace
`android/app/google-services.json` with the file downloaded from the buyer
project and regenerate `lib/firebase_options.dart` with FlutterFire CLI.

Never reuse the seller's Firebase service account or production project.

## 2. Customer identity

Build-time Android environment variables:

- `ANDROID_APPLICATION_ID` — e.g. `it.customer.fieldops`
- `ANDROID_APP_LABEL` — launcher label

Dart defines:

- `APP_DISPLAY_NAME`
- `APP_SUBTITLE`
- `BRAND_LOGO_ASSET`
- `SUPPORT_EMAIL`
- `API_BASE_URL`
- `APP_CHECK_DEBUG=false` for production

Put customer logo assets under `assets/brand/`. The default product identity
remains RadioTech when no customer override is supplied.

The Java/Kotlin namespace deliberately remains internal and does not need to
match the public Android application ID.

## 3. Buyer-owned signing

Generate or import the buyer's long-lived Android signing key and keep it only
in the buyer's secret manager / CI. Configure:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Changing the signing key after distribution prevents normal in-place updates.

## 4. Buyer backend

The production mobile app accepts a canonical HTTPS backend origin. The backend
must expose:

- `/api/v1/health` with `status=UP` and `service=radiotech-backend`
- `/actuator/health/readiness` with `status=UP`

The backend project and Firebase project must belong to the same customer
environment.

## 5. Build example

Example customer define file:

```json
{
  "API_BASE_URL": "https://operations.example.com",
  "APP_DISPLAY_NAME": "Example Operations",
  "APP_SUBTITLE": "Field Service",
  "BRAND_LOGO_ASSET": "assets/brand/customer-logo.png",
  "SUPPORT_EMAIL": "support@example.com",
  "APP_CHECK_DEBUG": false
}
```

Build with the buyer signing variables and:

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --release --dart-define-from-file=config/customer.json
```

For Android package/launcher customization also export
`ANDROID_APPLICATION_ID` and `ANDROID_APP_LABEL` before the build.

## 6. Acceptance before handover

Validate on a real managed Android device:

1. installation and signed upgrade
2. login and approval
3. App Check
4. task assignment and lifecycle
5. GPS check-in/check-out
6. offline queue, reconnect and conflict recovery
7. report PDF, signature, photo upload and history
8. FCM notification delivery and notification navigation
9. logout/session revocation
10. update through the buyer's Firebase App Distribution or Play channel

The buyer should retain the exact build number, source commit, APK/AAB hash,
signing certificate fingerprint and symbol files for every production release.
