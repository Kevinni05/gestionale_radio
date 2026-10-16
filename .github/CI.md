# GitHub Actions minute usage

`Gestionale Radio CI` runs on pull requests and pushes to `main` or `master`.

- Every run checks tracked files for private key material, including documentation changes.
- Documentation-only changes finish without installing Flutter or starting Android jobs.
- Other changes run dependency validation, analysis and Flutter tests first. Android QA compilation and native unit tests start only after these pass.
- The Android emulator starts only after QA compilation passes, and only for changes to Android, integration tests, services, models, app initialization, dependencies, runtime configuration or this CI workflow. Pure screen and theme changes still receive Flutter tests and Android compilation.
- The optional QA APK is retained for three days. Production artifact retention is unchanged.

To force all checks for any branch, open **Actions → Gestionale Radio CI → Run workflow**. Manual execution runs the full suite, but does not trigger Firebase distribution or production publishing.

When moving native storage or sync logic outside the currently matched paths, extend the `device` filter in `workflows/ci.yml`. All new non-documentation paths already receive analysis, Flutter tests and Android QA compilation.

The change reduces redundant work and stops expensive jobs after earlier failures. Actual minute savings depend on the changed files and test results; the private repository's included allowance is still shared by all its workflows.
