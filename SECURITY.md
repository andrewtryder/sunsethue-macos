# Security Policy

## Reporting a vulnerability

If you discover a security issue in this unofficial client, please open a private advisory on GitHub. Do not include live API keys in issues, pull requests, or public discussions.

## Secrets handling

- Never commit SunsetHue API keys, Keychain dumps, or provisioning profiles.
- Preview fixtures and tests must use fake keys and public sample coordinates only.
- Application logs must not include request headers or API keys.
- The API key is stored in the login Keychain only — never in Application Support JSON, UserDefaults, widgets timeline entries, or release DMGs.

## Free / unsigned distribution

GitHub Release builds (DMG) are intentionally unsigned and not notarized. Users must confirm Gatekeeper the first time they open the app. This is a tradeoff for distributing without an Apple Developer account. Prefer downloading only from the official repository releases page (or the README latest DMG link).

## Scope

Report issues that could expose credentials, write the API key to disk, or leak location data beyond the intended local Application Support / Keychain usage.
