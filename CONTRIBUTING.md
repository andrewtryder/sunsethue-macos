# Contributing

Thanks for your interest in improving SunsetHue for macOS.

This page covers **development**, packaging, and contribution workflow. End-user install and widget setup live in [README.md](README.md).

This project ships free unsigned GitHub Release builds without a paid Apple Developer account. App Sandbox and Team-ID App Groups remain in the repo for **local signed Personal Team widget development**; do not require a paid team for CI or the unsigned DMG.

## Development setup

1. Fork and clone the repository.
2. Install Xcode 15+ (Xcode 26 recommended) and optionally [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
3. Run `xcodegen generate` if you change `project.yml`.
4. Run `python3 scripts/verify_release_metadata.py` and `swift test --package-path .` before opening a pull request.
5. Build an unsigned DMG with `./scripts/package-unsigned.sh` or the `SunsetHue` scheme (`CODE_SIGNING_ALLOWED=NO`).

For local widget testing with a free Personal Team, see [Desktop widgets](README.md#desktop-widgets) in the README, or run:

```bash
./scripts/run-debug.sh
```

That builds a signed Debug app, installs it to `/Applications` for WidgetKit gallery discovery, refreshes PluginKit, and launches the app.

## Project layout

| Path | Purpose |
|------|---------|
| `Sources/SunsetHueCore` | Shared Swift package: API, models, Keychain, file storage, dates |
| `Tests/SunsetHueCoreTests` | Unit tests (no live network) |
| `SunsetHue` | Main macOS SwiftUI app |
| `SunsetHueWidget` | WidgetKit + App Intents extension |
| `scripts/package-unsigned.sh` | Builds unsigned GitHub Release DMG |
| `scripts/run-debug.sh` | Signed Debug build + PluginKit register + launch |
| `project.yml` | XcodeGen project definition |

## Identifiers

| Item | Value |
|------|--------|
| App bundle ID | `com.andrewtryder.SunsetHue` |
| Widget bundle ID | `com.andrewtryder.SunsetHue.Widget` |
| Shared data folder | `~/Library/Application Support/SunsetHue/` |
| URL scheme | `sunsethue` |
| Location deep link | `sunsethue://location/<location-id>` |
| App Group (signed Personal Team) | `$(TeamIdentifierPrefix)group.com.andrewtryder.SunsetHue` (macOS 15+ Team-ID form) |

Organization / copyright display name: **Andrew Tryder**.

## Building from source

```bash
# Unit tests (no live API)
swift test --package-path .

# Regenerate the Xcode project if you edit project.yml
xcodegen generate

# Unsigned build (default for this repo / CI)
xcodebuild -scheme SunsetHue -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- build
```

Or open `SunsetHue.xcodeproj` in Xcode and run the `SunsetHue` scheme (signing can stay off for the main app; widgets need Personal Team Debug signing — see the README).

## Testing

```bash
swift test --package-path .
```

Tests use `MockHTTPTransport` and fixtures. They never call the live API. Prefer tests for parser, validation, and timeline date logic.

## Packaging the unsigned DMG

```bash
python3 scripts/verify_release_metadata.py
./scripts/package-unsigned.sh
# → dist/SunsetHue-<version>-macos-unsigned.dmg
# → dist/SunsetHue-macos-unsigned.dmg   # stable name for latest/download
```

On `main`, release-please opens version PRs from Conventional Commits and, when merged, tags a release and uploads the unsigned DMG assets automatically.

### Unsigned DMG Keychain checklist

Before cutting a public release, validate Keychain against the **GitHub release DMG** (not an Xcode build):

1. Install the app into `/Applications`.
2. Save an API key in Settings → Account.
3. Quit and reopen; confirm the key still loads.
4. Reboot and reopen; confirm the key still loads.
5. Replace the app with a newer unsigned release build; confirm the old key still loads.
6. Launch from Finder and from the menu bar login item; confirm credentials work in both paths.

Unsigned builds use the traditional login Keychain when Data Protection Keychain access is unavailable. Signed Personal Team builds use the Data Protection Keychain.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/). CI enforces this with commitlint on pull requests.

- `feat:` new user-facing capability (minor semver bump)
- `fix:` bug fix (patch semver bump)
- `feat!:` / `fix!:` or a `BREAKING CHANGE:` footer (major semver bump)
- `test:` tests only
- `docs:` documentation only
- `refactor:` internal change without behavior change
- `chore:` maintenance, CI, tooling

Examples:

```text
feat: add large widget three-day layout
fix: preserve forecast cache on timeout
test: cover Retry-After HTTP-date parsing
```

## Versioning and releases

Versions are **semver** (`MAJOR.MINOR.PATCH`), managed by [release-please](https://github.com/googleapis/release-please) from Conventional Commits on `main`.

Keep these in sync (release-please updates them; CI verifies):

| File | Field |
|------|--------|
| [Config/Version.xcconfig](Config/Version.xcconfig) | `MARKETING_VERSION` → app `CFBundleShortVersionString` |
| [project.yml](project.yml) | `MARKETING_VERSION` |
| [Sources/SunsetHueCore/Constants.swift](Sources/SunsetHueCore/Constants.swift) | `marketingVersion` (User-Agent) |
| [.release-please-manifest.json](.release-please-manifest.json) | release-please manifest |

When a release PR merges, GitHub Actions builds and attaches:

- `SunsetHue-<version>-macos-unsigned.dmg`
- `SunsetHue-macos-unsigned.dmg` (stable name for `releases/latest/download/`)

## Pull requests

- Keep changes focused.
- Do not commit API keys, provisioning profiles, or precise private coordinates.
- Update [README.md](README.md) for user-facing install or widget steps; update this file for developer setup.
- Prefer tests for parser, validation, and timeline date logic.

## Code style

- Prefer native Apple frameworks; avoid third-party dependencies unless necessary.
- Keep user-facing errors concise and free of secrets.
- Use Swift Concurrency (`async`/`await`) for networking.
