# Contributing

Thanks for your interest in improving SunsetHue for macOS.

## Development

1. Fork and clone the repository.
2. Install Xcode 15+ and optionally XcodeGen (`brew install xcodegen`).
3. Run `xcodegen generate` if you change `project.yml`.
4. Run `python3 scripts/verify_release_metadata.py` and `swift test` before opening a pull request.
5. Build an unsigned DMG with `./scripts/package-unsigned.sh` or the `SunsetHue` scheme (`CODE_SIGNING_ALLOWED=NO`).

This project ships free unsigned GitHub Release builds without a paid Apple Developer account. App Sandbox, Team-ID App Groups, and Keychain Sharing remain in the repo for **local signed Personal Team widget development**; do not require a paid team for CI or the unsigned DMG.

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
- Update README when setup or identifiers change.
- Prefer tests for parser, validation, and timeline date logic.

## Code style

- Prefer native Apple frameworks; avoid third-party dependencies unless necessary.
- Keep user-facing errors concise and free of secrets.
- Use Swift Concurrency (`async`/`await`) for networking.
