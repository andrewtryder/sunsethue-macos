# SunsetHue for macOS

An unofficial native macOS menu-bar app for [SunsetHue](https://sunsethue.com) sunrise and sunset quality forecasts across multiple saved locations.

**This project is unofficial and is not reviewed, endorsed, or supported by SunsetHue or Apple.**

<p>
  <img src="docs/images/app-sandown.png" alt="SunsetHue macOS app showing Sandown sunrise and sunset forecast quality" width="720" />
</p>

## Features

- **Compact menu-bar forecast:** View current and upcoming forecast quality for all saved locations at a glance.
- **Accurate event timing:** Next sunrise/sunset with exact time, countdown, and quality score rating.
- **Multi-day main forecast:** Detailed multi-day forecast cards showing cloud layers (low/medium/high), temperature, humidity, and visibility.
- **Background refresh:** Automatically refreshes forecasts in the background via `NSBackgroundActivityScheduler`.
- **Launch at Login:** Runs quietly in the background without needing the main window open.
- **Per-location notifications:** Granular notification rules and quality score thresholds for each location.
- **Location reordering:** Drag-and-drop location ordering reflected across sidebar and menu bar.
- **Privacy-safe diagnostics:** Copy/export sanitized diagnostics for troubleshooting without exposing personal locations or credentials.
- **Secure Keychain storage:** SunsetHue API key is stored strictly in your macOS login Keychain.
- **Universal binary:** Native support for both Apple Silicon (arm64) and Intel (x86_64).

## Requirements

- macOS 15 or newer
- SunsetHue API key from [sunsethue.com/dev-api](https://sunsethue.com/dev-api)

## Download

[**Download SunsetHue for macOS (DMG)**](https://github.com/andrewtryder/sunsethue-macos/releases/latest/download/SunsetHue-macos-unsigned.dmg)

The GitHub release is an **unsigned universal macOS app**. It does not require Xcode, an Apple ID, or an Apple Developer account.

### Installation

1. Download and open `SunsetHue-macos-unsigned.dmg`.
2. Drag **SunsetHue.app** into your **Applications** folder.
3. On first launch:
   - **Right-click** `SunsetHue.app` → **Open** → **Open**, or
   - Go to **System Settings → Privacy & Security → Open Anyway** if macOS Gatekeeper blocks the initial run.
4. Enter your SunsetHue API key in **Settings → Account**.
5. Add one or more locations.

*(Note: The one-time Gatekeeper confirmation occurs because SunsetHue is distributed free directly on GitHub without paid Apple Developer ID signing or notarization. SunsetHue does not require disabling Gatekeeper globally.)*

## Using SunsetHue

- **Menu-Bar Popup:** Click the menu bar icon to view all configured locations with immediate quality badges. Click any row to deep-link directly to that location in the main window.
- **Main Window:** View comprehensive multi-day timelines, detailed atmospheric metrics, and opportunity summaries.
- **Background Refresh:** While SunsetHue is running (including menu bar-only mode), stale forecasts update automatically in the background.
- **Launch at Login:** Enable in Settings → General to keep forecasts updated without manual app launches.
- **Notifications:** Configure automated alerts in Settings → Notifications with custom quality thresholds (e.g. notify if sunset quality ≥ 75%).
- **Forecast Days:** Configure 1, 2, or 3 visible forecast days per location in Settings → General.

## Privacy

- **Keychain Only:** Your API key is stored exclusively in the macOS Keychain (`api-key-v2`) and never written to disk files or logs.
- **Local Storage:** App settings and forecast caches are stored locally in `~/Library/Application Support/SunsetHue/`.
- **Zero Telemetry:** SunsetHue contains no analytics, telemetry, crash trackers, or third-party SDKs.
- See [PRIVACY.md](PRIVACY.md) for the complete privacy policy.

## Updating

1. Download the latest `SunsetHue-macos-unsigned.dmg` from GitHub Releases.
2. Quit the running SunsetHue app.
3. Replace `/Applications/SunsetHue.app` with the new version from the DMG.
4. Launch SunsetHue. Your saved locations, settings, and API key are preserved automatically.

## Development

For standard unsigned macOS development and testing:

```bash
./scripts/run-debug.sh
```

This builds the unsigned Debug app, strips any widget extension, copies the app to `/Applications/SunsetHue.app`, and launches it.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development workflows, test commands, and project architecture.

## Building a release locally

Public release binaries are built and packaged locally on macOS rather than cloud runners:

```bash
./scripts/release-local.sh v1.2.0
```

Release Please creates the version tag and release entry on GitHub; `release-local.sh` builds, tests, packages, checksums, and uploads the universal unsigned DMG.

## Desktop widget status

WidgetKit support exists in the source tree but is currently **shelved** and is not included in standard GitHub releases.

Free Personal Team widget builds require periodic reprovisioning (typically every 7 days) and are not the supported distribution path.

For experimental widget development using a Personal Team Apple ID, see [CONTRIBUTING.md](CONTRIBUTING.md#experimental-widget-development).

<p>
  <img src="docs/images/widget-sandown.png" alt="SunsetHue desktop widgets (shelved/experimental)" width="360" />
</p>

## License

MIT — see [LICENSE](LICENSE).
