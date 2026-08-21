# SunsetHue Release Readiness Checklist

This document tracks runtime invariants, platform integration boundaries, and verification criteria for SunsetHue releases.

## Core Architectural Invariants

### 1. Menu-Bar Popup Experience
- [x] One compact row per configured location.
- [x] Natural `VStack` sizing for 1–7 locations without blank/collapsed row regions.
- [x] Fixed-height `ScrollView` for 8+ locations with visible footer controls.
- [x] Long location names truncate cleanly before trailing event/time/quality metrics.
- [x] Stable selected-location permanent menu-bar label.

### 2. Settings & Menu Commands
- [x] Exactly one native macOS `Settings...` command (⌘,).
- [x] Menu-bar popup Settings button activates the standard Settings scene.
- [x] No duplicate Settings scenes or windows.

### 3. App Group & Sandboxing
- [x] Personal Team signed builds use `<TEAMID>.group.com.andrewtryder.SunsetHue`.
- [x] Unsigned builds fall back safely to `~/Library/Application Support/SunsetHue/` without probing App Groups.
- [x] Raw `group.com.andrewtryder.SunsetHue` is NEVER queried (prevents recurring privacy prompts).
- [x] Widget is a read-only consumer of shared cache/settings (no API keys, no Keychain access, no network calls).

### 4. Forecast & Rollover
- [x] Minimum 2-day operational fetch/cache horizon maintained even when `forecastDays = 1`.
- [x] Post-sunset rollover seamlessly selects tomorrow's sunrise without "No forecast available" regressions.
- [x] User-visible forecast horizon (`forecastDays`) remains distinct from operational cache horizon.

### 5. Refresh Coordinator & Concurrency
- [x] Single-flight concurrency per location (coalesces duplicate concurrent requests).
- [x] Forced refreshes (`force: true`) are not swallowed by non-forced operations.
- [x] Rejected/stale cache updates produce zero persistence side effects or widget reloads.
- [x] Exponential backoff and Retry-After headers strictly respected.

### 6. Background Scheduling & Lifecycle
- [x] `NSBackgroundActivityScheduler` used for background refreshes.
- [x] Refreshes trigger on wake (`applicationDidWake`) and activation (`applicationDidBecomeActive`).
- [x] Strict concurrency checking (Swift 6 readiness) enabled with no data races.

---

## Verification Commands

Execute the following test suite and release validation commands before any release:

```bash
# 1. Swift Package tests
swift test --package-path .

# 2. Thread Sanitizer
swift test --package-path . --sanitize=thread

# 3. Address Sanitizer
swift test --package-path . --sanitize=address

# 4. Project file synchronization
xcodegen generate
git diff --exit-code -- SunsetHue.xcodeproj

# 5. Release metadata verification
python3 scripts/verify_release_metadata.py
```
