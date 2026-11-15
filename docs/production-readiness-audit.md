# Production-Readiness Audit — SunsetHue for macOS

Date: 2026-11-14
Scope: `SunsetHue/` (app), `Sources/SunsetHueCore/` (core logic), `SunsetHueWidget/` (widget),
packaging scripts, CI. ~14.8k lines of Swift, 219 unit tests, strict-concurrency build
(`SWIFT_STRICT_CONCURRENCY: complete`), macOS 15+.

## Verdict

**Production-ready for an unsigned, non-MAS distribution.** No blocking issues found.
The findings below are ranked; P2/P3 items are quality debt, not correctness bugs.

---

## 1. Lifecycle — PASS (was the critical bug, now fixed)

| Check | Status | Notes |
|---|---|---|
| Popup dismissal keeps app alive | PASS | `AppDelegate.applicationShouldTerminateAfterLastWindowClosed` returns `false` (fixed in `7bc931f`); verified with real CGEvent clicks. |
| Single-instance handling | PASS | Secondary instances forward URLs via `DistributedNotificationCenter`, activate the primary, then `NSApp.terminate`. |
| Activation policy | PASS | `.accessory` (menu-bar-only) vs `.regular` applied via `AppPresentationModeController`; re-opening from Dock posts `reopenMainWindowNotification`. |
| Window lifecycle | PASS | Single `Window(id: "main")` with `openWindow(id:)` — no window duplication. |

**P2 (lifecycle race, low likelihood):** in `AppDelegate.application(_:open:)`, a secondary
instance calls `activateExistingInstance()` then `NSApp.terminate(nil)` immediately. If the
forwarding notification is delivered after the primary finishes handling the URL, ordering is
fine; but `terminate:` during `-application:open:` is not guaranteed to deliver the distributed
notifications first. Safer: post notifications, then `DispatchQueue.main.async { NSApp.terminate(nil) }`.
Not observed failing in testing; queued as follow-up.

**P3:** `applicationDidFinishLaunching` reads `menuBarOnlyMode` from `UserDefaults.standard`
while `SunsetHueApp` binds it via `@AppStorage` — consistent today, but two sources of truth
for one preference.

## 2. Concurrency — PASS

| Check | Status | Notes |
|---|---|---|
| Strict concurrency | PASS | Project builds with `SWIFT_STRICT_CONCURRENCY: complete`; only pre-existing Swift-6-mode *warnings* remain in `AppDelegate` notification delegates (not errors). |
| State isolation | PASS | All mutable app state on `@MainActor AppModel`; caches/stores are actors (`FileSettingsStore`, `FileForecastCache`, `ForecastRefreshCoordinator`, `DailyNotificationScheduler`, `RefreshActivityRecorder`). |
| Cross-process file access | PASS | All shared-file IO goes through `NSFileCoordinator` (`CoordinatedFileIO`) with atomic temp-file + rename writes. |
| Refresh task hygiene | PASS | `scheduleNextRefresh` cancels prior task; generation counters discard stale refresh results after location edits/removals. |
| Notification wait | PASS | `waitForForegroundPresentation` resumes its continuation exactly once (lock-guarded), removes its observer, and times out. |

**P3:** `try? await Task.sleep` in two schedulers swallows cancellation; harmless because the
surrounding code re-checks `Task.isCancelled`, but explicit `try` with `catch { return }` would
be clearer.

## 3. Error handling — PASS

- All network/parse/keychain failures funnel through `SunsetHueError` with distinct
  `userMessage` (user-facing) and `diagnosticDescription` (logs) — messages never contain
  credentials or headers.
- Transient vs permanent errors are classified (`isTransient`) and drive retry/backoff;
  rate-limit respects `retryAfter`.
- Corrupt/too-large storage is quarantined (renamed `.corrupt-<ts>`), never silently deleted;
  the app boots with defaults and shows a recovery banner.
- Storage migration is idempotent, copies via temp+rename, never deletes sources, and reports
  per-file failures.

## 4. Credentials — PASS

- API key lives only in Keychain (`KeychainCredentialStore`): Data-Protection Keychain first,
  login-Keychain fallback for unsigned builds (the exact failure mode of unsigned DMGs), with
  stale-copy cleanup across backends.
- `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — reasonable for a menu-bar utility.
- Widget never reads credentials (its entitlements contain only sandbox + app group).
- Logs use fixed diagnostic strings; no key material is ever logged or embedded in errors.
- `InMemoryCredentialStore` exists for tests/previews only.

**P3:** `AppModel.apiKeyDraft` (`@Published var`) briefly holds the key in memory while the
settings sheet is open. Standard practice; noted for completeness.

## 5. Unsigned packaging — PASS

- `scripts/package-unsigned.sh`: universal (arm64 + x86_64) Release build, `CODE_SIGN_IDENTITY=-`
  (ad-hoc), strips the widget extension for distribution (unsigned extensions fail to load),
  DMG with drag-to-install layout and a README that sets expectations (unsigned, right-click →
  Open, key stored in Keychain).
- `verify_universal_binary` / `verify_widget_absent` assertions guard both failure modes.
- Storage falls back to `~/Library/Application Support/SunsetHue` when no team-app-group
  entitlement resolves (unsigned builds), with one-way migration into the group container once
  a signed build appears.
- CI now builds the unsigned app and sanity-checks the produced bundle (executable present,
  plist readable).

## 6. Quality gates in place

- `swiftformat --lint` — clean (config: `.swiftformat`).
- `swiftlint --strict` — clean (config: `.swiftlint.yml`; thresholds documented).
- 219/219 unit tests — pass.
- Pre-commit hook (`.githooks/pre-commit`, enable via `git config core.hooksPath .githooks`)
  gates staged Swift files.
- CI runs the full gate on every push/PR.

## Follow-up backlog (non-blocking)

1. **P2** — Defer `NSApp.terminate` one runloop turn in secondary-instance URL forwarding.
2. **P2** — Split `AppModel` (693 lines) and `SunsetHueSettingsView` (996 lines) into focused
   types; `ForecastRefreshCoordinator.refreshAllLocations` (209 lines) into phases.
3. **P3** — Consolidate `menuBarOnlyMode` reads into `@AppStorage` only.
4. **P3** — Replace `try? await Task.sleep` cancellation swallowing with explicit handling.
5. **P3** — Wrap app-group writes in `NSFileCoordinator` from the widget side as well (main app
   already coordinates).
