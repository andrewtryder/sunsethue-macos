# Contributing to SunsetHue for macOS

Thanks for your interest in contributing to SunsetHue for macOS.

This guide covers **local development**, testing, unsigned distribution packaging, local release publishing, and optional experimental widget development.

End-user installation instructions live in [README.md](README.md).

---

## Normal Development Setup

SunsetHue is developed and distributed primarily as an **unsigned macOS application**. No paid Apple Developer account, provisioning profile, or signing identity is required for normal development.

1. Clone the repository.
2. Ensure Xcode 15+ (macOS 15+ SDK) is installed.
3. (Optional) Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) if editing `project.yml`.
4. Build and launch the unsigned development app:
   ```bash
   ./scripts/run-debug.sh
   ```

`./scripts/run-debug.sh` will:
- Regenerate the Xcode project with `xcodegen` if available.
- Build the `SunsetHue` scheme in `Debug` configuration with code signing disabled.
- Strip any WidgetKit extension from the bundle so it behaves identically to the unsigned public release.
- Terminate any running SunsetHue instance and install to `/Applications/SunsetHue.app`.
- Launch the newly built app.

To skip `/Applications` installation during debug runs:
```bash
INSTALL_TO_APPLICATIONS=0 ./scripts/run-debug.sh
```

---

## Testing & Quality Assurance

Run the test suite before submitting pull requests:

```bash
# Standard unit tests (mocked networking, no live API required)
swift test --package-path .

# Concurrency and thread safety verification
swift test --package-path . --sanitize=thread

# Memory safety validation
swift test --package-path . --sanitize=address
```

Verify version metadata consistency across manifests and xcconfigs:
```bash
python3 scripts/verify_release_metadata.py
```

---

## Project Layout

| Path | Purpose |
|------|---------|
| `Sources/SunsetHueCore` | Shared Swift package: API client, models, Keychain, storage, date formatting |
| `Tests/SunsetHueCoreTests` | Comprehensive unit tests (using `MockHTTPTransport` and recorded fixtures) |
| `SunsetHue` | Main macOS SwiftUI application and Menu Bar Extra |
| `SunsetHueWidget` | Shelved WidgetKit + App Intents extension (experimental) |
| `scripts/lib/app-tools.sh` | Shared shell utilities for stripping widgets and verifying binaries |
| `scripts/run-debug.sh` | Canonical unsigned Debug build, install, and launch script |
| `scripts/package-unsigned.sh` | Canonical unsigned universal DMG packaging script |
| `scripts/release-local.sh` | Local release build, test, package, checksum, and upload script |
| `scripts/run-widget-debug.sh` | Experimental Personal Team signed widget runner |
| `project.yml` | XcodeGen project configuration |

---

## Identifiers

| Item | Value |
|------|--------|
| App bundle ID | `com.andrewtryder.SunsetHue` |
| Widget bundle ID | `com.andrewtryder.SunsetHue.Widget` |
| Unsigned Storage | `~/Library/Application Support/SunsetHue/` |
| URL Scheme | `sunsethue` |
| Location Deep Link | `sunsethue://location/<location-id>` |
| App Group (Signed Dev) | `$(TeamIdentifierPrefix)group.com.andrewtryder.SunsetHue` |

Organization / copyright display name: **Andrew T Ryder**.

---

## Packaging the Unsigned DMG

To build the universal unsigned distribution DMG locally:

```bash
./scripts/package-unsigned.sh
```

Artifacts produced:
- `dist/SunsetHue-<VERSION>-macos-unsigned.dmg` (versioned release DMG)
- `dist/SunsetHue-macos-unsigned.dmg` (stable name for direct download links)

The packaging script verifies:
1. Universal binary architecture (`arm64` and `x86_64` via `lipo`).
2. WidgetKit extension is stripped from the bundle.
3. DMG includes the drag-to-install `/Applications` link and `README-FIRST.txt`.

---

## Local Release Publishing

Release binaries are built and packaged on macOS rather than cloud runners:

1. **Release Please** creates the version PR and tag (`vX.Y.Z`) on GitHub when Conventional Commits merge to `main`.
2. On your Mac, run the local release script to test, build universal binaries, checksum, and upload the DMG assets to GitHub:

```bash
# Test release packaging locally without uploading (Dry Run):
./scripts/release-local.sh --dry-run v1.2.0

# Build, validate, package, checksum, and upload assets to GitHub Release:
./scripts/release-local.sh v1.2.0
```

To run full sanitizer test passes during release packaging:
```bash
FULL_VALIDATION=1 ./scripts/release-local.sh v1.2.0
```

---

## Unsigned DMG Keychain Checklist

Before cutting a public release, validate Keychain behavior against the **unsigned DMG** build:

1. Install SunsetHue from the generated DMG into `/Applications`.
2. Save your API key in **Settings → Account**.
3. Quit and relaunch SunsetHue; confirm the key loads without prompting.
4. Reboot the Mac and launch SunsetHue; confirm credentials persist.
5. Replace the application with a newer unsigned DMG build; confirm settings and API key persist across upgrades.

---

## Experimental Widget Development

> **Note:** Desktop widgets via WidgetKit are currently **shelved** for public releases because macOS requires signed App Group entitlements that expire periodically on free Apple ID Personal Teams.

To build and test the experimental desktop widgets locally with a free Apple ID:

1. Create a `Config/Local.xcconfig` file from the example:
   ```bash
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```
2. Open Xcode → Settings → Accounts → select your Apple ID → copy your 10-character **Team ID**.
3. Set `DEVELOPMENT_TEAM = YOURTEAMID` in `Config/Local.xcconfig`.
4. Build, sign, register, and launch the widget-enabled build:
   ```bash
   ./scripts/run-widget-debug.sh
   ```
5. Right-click the desktop → **Edit Widgets** → add **SunsetHue**.

*Personal Team provisioning profiles expire every 7 days. Re-run `./scripts/run-widget-debug.sh` to renew.*

---

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):
- `feat:` new user-facing functionality (minor semver bump)
- `fix:` bug fix (patch semver bump)
- `feat!:` or `fix!:` with breaking change footer (major semver bump)
- `test:` test suite additions or adjustments
- `docs:` documentation updates
- `refactor:` code refactoring without behavior change
- `chore:` maintenance, build scripts, release tooling
