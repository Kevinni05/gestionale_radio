# RadioTech Mobile — customer white-label build

The mobile app can be delivered per customer without changing business logic.
Branding is supplied at build time, while Firebase registration, signing and the
application/bundle identifier are customer-owned release assets.

## Build-time branding

Supported Dart defines:

```text
APP_NAME
APP_DISPLAY_NAME
APP_SUBTITLE
APP_COMPANY
APP_SUPPORT_EMAIL
APP_PDF_BRAND
APP_ASSET_PREFIX
API_BASE_URL
APP_CHECK_DEBUG
```

Example:

```powershell
.\scripts\build-release.ps1 \
  -ApiBaseUrl https://ops.acme.example \
  -BuildNumber 1 \
  -AppName "Acme Field Ops" \
  -AppSubtitle "Network Operations" \
  -CompanyName "Acme S.p.A." \
  -SupportEmail "it-support@acme.example" \
  -AndroidApplicationId "com.acme.fieldops"
```

The Android launcher label is supplied by `ANDROID_APP_NAME` automatically by
the release script. The Android application ID can be overridden with
`ANDROID_APPLICATION_ID`.

## Customer Firebase project

For a new buyer deployment:

1. Create a Firebase/GCP project owned by the customer.
2. Register the final Android application ID and iOS bundle ID.
3. Run FlutterFire CLI against the customer project to regenerate
   `lib/firebase_options.dart`, `android/app/google-services.json` and the
   Apple Firebase configuration.
4. Register the production signing certificate fingerprints.
5. Configure App Check production providers.
6. Configure Authentication providers and FCM/APNs.
7. Keep service-account credentials out of this repository.

Do not reuse the developer Firebase project for a customer production tenant.

## Signing and update identity

Android upgrades require the same application ID and signing key as the
installed app. For a new customer, create a customer-controlled signing key
before the first production build and store it in the customer's secret
manager/CI.

Expected signing environment:

```text
ANDROID_KEYSTORE_PATH
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

The private keystore must never be committed.

## App Distribution / Play

Pilot deployments can use the customer's Firebase App Distribution project.
Production fleets should normally use the customer's Google Play organization,
Managed Google Play/EMM, or another approved enterprise distribution channel.

The CI pipeline can publish signed builds when the customer-owned Firebase
distribution credentials and signing secrets are configured.

## Acceptance

Before handover, verify on a real device:

- login, approval and SSO/MFA if enabled;
- push notifications;
- task lifecycle and GPS check-in/check-out;
- offline mode, reconnect and manual synchronization;
- report generation, signature, photos and attachments;
- report history/PDF;
- backend identity/readiness;
- update installation over the previous signed version.

The package/bundle identifier migration is intentionally explicit because it is
part of the customer's permanent mobile identity, not ordinary branding.
