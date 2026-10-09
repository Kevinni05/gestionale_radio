# RadioTech Mobile — Enterprise Readiness Audit

Updated: 9 October 2026

## Executive status

RadioTech Mobile has moved beyond the original functional prototype. The current
architecture includes authenticated backend-only report storage, tenant-aware
sessions, device/session binding, App Check, offline queueing, idempotent writes,
bounded network retries, PDF/signature/photo reporting, push notifications,
production endpoint enforcement, release signing checks and automated Flutter
analysis/tests/builds.

The application is suitable for controlled enterprise pilot distribution once
the CI release pipeline, backend deployment and real-device acceptance gates are
green. "Enterprise ready" here means the engineering controls are implemented;
it is not a substitute for an organization's own security/compliance review.

## Implemented controls

- Firebase Authentication with tenant/role claims and approval gating.
- Firebase App Check with debug mode forbidden in release builds.
- HTTPS-only production API endpoint validation.
- Backend identity validation using `service=radiotech-backend` and `status=UP`.
- Backend-routed private report attachments; no production direct client upload.
- Stable idempotency keys for report submission and task lifecycle writes.
- Replay-safe HTTP retry/backoff for transient failures.
- Durable offline synchronization with failed-action retention and manual recovery.
- Local staged attachment validation and bounded storage usage.
- Actor/tenant ownership checks before replaying queued work.
- Authenticated report history and legacy-document recovery.
- GPS-aware task completion, signature, photos and locally generated PDF reports.
- FCM notifications with local notification routing.
- Production signing validation and App Check release guard.
- CI checks for analysis, tests, Android build and committed secret/key material.
- Generated QA artifacts excluded from source control.

## Runtime hardening in this revision

- Firebase and App Check initialize before the offline/API synchronization layer.
- Notification bootstrap is idempotent to prevent duplicate listeners.
- Notification diagnostics no longer log user identifiers or full message payloads.
- Backend settings accept only a healthy RadioTech backend identity.
- The `uuid` dependency is constrained to the supported v4 line instead of `any`.

## Release gates

A production/pilot build should ship only when all of the following are true:

1. CI analysis, tests and Android build are green.
2. APK/AAB is signed with the stable organization-controlled signing key.
3. App Check production provider is configured and debug mode is disabled.
4. The configured backend reports RadioTech identity and healthy/readiness state.
5. Firebase App Distribution or Play Internal Testing publishes the exact signed build.
6. A real Android device validates login, task lifecycle, GPS, offline/reconnect,
   report PDF, photo/signature upload, history and push notifications.
7. Service-account and signing credentials remain only in protected CI secrets.
8. Backend authorization/audit controls are independently validated for the target tenant.

## Remaining platform/program risks

- Android package ID is still `com.example.gestionale_radio`. Changing it is a
  migration, not a cosmetic rename: Firebase app registration, App Check,
  signing/update compatibility and deployed installations must be coordinated.
  Do not change it in an ordinary hardening PR.
- iOS production signing/APNs/App Check requires validation on macOS/Xcode.
- Formal compliance requirements (for example ISO 27001 controls, SOC 2,
  retention policies or customer-specific regulatory obligations) are
  organizational processes and require separate evidence/review.
- Operational observability can be extended with an approved crash/error telemetry
  platform, with explicit payload-redaction rules.

## Engineering conclusion

The codebase now has the core reliability and security mechanisms expected from
an enterprise field-operations mobile client. Remaining work is primarily
release governance, external platform configuration, real-device acceptance and
the deliberate package-ID migration if/when the product moves to a permanent
store identity.
