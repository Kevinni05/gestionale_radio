# Report materials — Android 1.5.1+2022

The report form reads the actual company warehouse from `GET /api/v1/operator/me/inventory`. Search by name or SKU, then select the quantity used. Submission includes inventory ID, SKU, name and quantity; the four fixed example parts and free-text stock entries have been removed.

The last successful catalog is cached per company and operator for offline work. An old draft automatically matches only a unique exact name or SKU. Unmatched selected parts remain visible for removal and must be replaced with real catalog items before sending. Backend stock availability is checked during approval.

Already submitted reports do not need another signature or submission. The updated web review dialog lets an authorized reviewer map their old material names to actual stock, preserving the signed PDF and preventing duplicate consumption.

The APK and AAB use the existing production signing key and `https://radiotechwebapp.onrender.com`. The release script now has valid PowerShell syntax and retains the expected-certificate check configured through `ANDROID_EXPECTED_SIGNING_SHA256`.

Verification: Flutter analysis, full widget/unit suite, release APK/AAB compilation and production certificate verification. The send-preview regression tests select a real SKU and assert the exact stable material ID sent, including retry after failure on a 320 px display with enlarged text.
