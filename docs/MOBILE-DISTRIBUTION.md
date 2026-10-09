# Mobile distribution via Firebase App Distribution

CI can publish a signed Android APK after successful pushes to `main`.

## Repository secrets

Configure these buyer-owned GitHub Actions secrets:

- `FIREBASE_APP_DISTRIBUTION_SERVICE_ACCOUNT_JSON`
- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Optional repository variables:

- `FIREBASE_APP_DISTRIBUTION_TESTERS` — comma-separated tester emails
- `FIREBASE_APP_DISTRIBUTION_GROUPS` — comma-separated App Distribution groups

The service account must belong to the Firebase project used by the build and
have only the permissions required for App Distribution.

## Version codes

Automatic CI builds use a monotonically increasing Android build number derived
from the GitHub Actions run number with a high baseline. This avoids publishing
an APK whose `versionCode` is lower than a previously installed enterprise
build.

Store releases should still use an explicitly governed semantic version and
build number in the production-release workflow.

## Signing

Every Android update must use the same buyer-owned signing certificate as the
installed application. Never commit the keystore. If a device currently has a
debug-signed build, the first production-signed installation may require a
one-time uninstall/reinstall after backing up any local-only data.

## Tester flow

After accepting the Firebase App Distribution invitation, testers can use the
Firebase tester experience to receive releases. Android still requires the user
or device-management policy to approve installation of an APK update.

For a new customer environment, follow
`docs/CUSTOMER-PROVISIONING.md` before enabling automatic distribution.
