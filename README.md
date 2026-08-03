# SunsetHue for macOS

Unofficial native macOS app (and optional WidgetKit extension) that shows SunsetHue sunrise and sunset forecast quality for one or more saved locations.

**This project is unofficial and is not reviewed, endorsed, or supported by SunsetHue or Apple.**

## Screenshots

<p>
  <img src="docs/images/app-sandown.png" alt="SunsetHue macOS app showing Sandown sunrise and sunset forecast quality for today" width="720" />
</p>

<p>
  <img src="docs/images/widget-sandown.png" alt="SunsetHue small, medium, and large desktop widgets for Sandown" width="360" />
</p>

## Requirements

- macOS 15 or newer
- A SunsetHue API key from [sunsethue.com/dev-api](https://sunsethue.com/dev-api)

## Download and open

[Download SunsetHue for macOS (DMG)](https://github.com/andrewtryder/sunsethue-macos/releases/latest/download/SunsetHue-macos-unsigned.dmg)

GitHub Releases ship an **unsigned** DMG (main app only). No paid Apple Developer Program is required to use the app.

1. Open the DMG and drag **SunsetHue** into **Applications**.
2. Open the app once via **Right-click** → **Open** → **Open**, or use **System Settings → Privacy & Security → Open Anyway** if macOS blocks the first launch.  
   (Gatekeeper blocks unsigned apps until you confirm once.)
3. Add your SunsetHue API key (Settings → Account) and at least one location.

## Obtaining an API key

1. Visit [https://sunsethue.com/dev-api](https://sunsethue.com/dev-api).
2. Create an API key with SunsetHue.
3. Paste it into **Settings → Account**. It is stored **only** in the macOS Keychain (never in disk files or logs).

After upgrading to the current architecture, re-enter your API key once in Settings → Account.

## Privacy and data on your Mac

- API key: login Keychain only (`api-key-v2`)
- Settings and forecast cache: `~/Library/Application Support/SunsetHue/`
- See [PRIVACY.md](PRIVACY.md) for the full statement

## Desktop widgets

macOS **will not list** a WidgetKit extension from the unsigned GitHub Release DMG. That is why SunsetHue does not appear under Edit Widgets when you run the free download.

To enable the widget on your own Mac (still free — no $99 program):

1. Create a free [Apple ID](https://appleid.apple.com) if you do not have one.
2. Install [Xcode](https://developer.apple.com/xcode/) from the Mac App Store.
3. Xcode → Settings → Accounts → add that Apple ID.
4. Clone this repository, then copy `Config/Local.xcconfig.example` → `Config/Local.xcconfig` and set your **Personal Team** ID, **or** in the `SunsetHue` and `SunsetHueWidget` targets enable **Automatically manage signing** and pick your Personal Team.
5. Confirm both targets have **App Sandbox** and **App Groups** (`$(TeamIdentifierPrefix)group.com.andrewtryder.SunsetHue`). The widget does **not** need network or Keychain entitlements.
6. **Product → Run** from Xcode (Debug, signed — not the unsigned Release DMG).  
   Or from a terminal: `./scripts/run-debug.sh`
7. Right-click the desktop → **Edit Widgets** → search **SunsetHue**.

If the widget shows **Open SunsetHue to add a location** while the app already has locations, or an old unsigned placeholder: on macOS 15+ the widget cannot read iOS-style `group.*` App Groups (silent deny). This project uses the Team-ID-prefixed group `$(TeamIdentifierPrefix)group.com.andrewtryder.SunsetHue`. Also remove/re-add the widget after replacing a stale `/Applications/SunsetHue.app`, and do not open unsigned Release DMG builds while testing widgets.

## Known widget limitations

- WidgetKit controls real refresh timing; 6 / 12 / 24 hour intervals are preferences
- Transient failures keep the last cached forecast in the app
- Auth failures prompt you to update the API key in Settings → Account

## License

MIT — see [LICENSE](LICENSE).

## Developers and contributors

Build instructions, project layout, identifiers, tests, and release notes live in [CONTRIBUTING.md](CONTRIBUTING.md).
