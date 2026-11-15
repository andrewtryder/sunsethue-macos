# Menu Bar Popup — Manual Verification Matrix

These steps verify behavior that requires real menu bar interaction (the
`.menuBarExtraStyle(.window)` popup and AppKit status-item event handling), which
unit tests cannot exercise. Unit-test coverage for the presentation logic lives in
`Tests/SunsetHueCoreTests/MenuBarPopupPresentationTests.swift`.

Build and launch the debug app with:

```bash
./scripts/run-debug.sh
```

## Background

The original bug: dismissing the popup quit the entire process, because AppKit's
`applicationShouldTerminateAfterLastWindowClosed` defaults to `true` and the popup
was frequently the only open window. `AppDelegate` now returns `false`. Every step
below doubles as a regression check that the app **keeps running**.

Automated verification recipe (used during development): post a real mouse click
with `CGEvent` at the status item, then poll `CGWindowListCopyWindowInfo` for a
window at `kCGWindowLayer == 101`. Note that accessibility-API clicks
(`AXPress`, System Events `click`) do not reliably open `MenuBarExtra` popups and
must not be used to judge this behavior.

## Matrix

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 1 | Open / stays open | Click the status item once. | Popup appears below the item and remains open indefinitely. |
| 2 | Dismiss: outside click | With popup open, click any other part of the screen. | Popup closes. **App keeps running** (status item remains). |
| 3 | Dismiss: status-item toggle | With popup open, click the status item again. | Popup closes. App keeps running. |
| 4 | Dismiss: Escape | With popup open, press Escape. | Popup closes. App keeps running. |
| 5 | Repeated clicks | Click the status item 5× rapidly. | Popup toggles open/closed; app never quits. |
| 6 | Zero locations | Remove all locations (fresh install also works). | Popup shows the "No locations yet" empty state; Open/Settings/Quit controls work. |
| 7 | One location | Configure exactly one location. | Single row renders; open/dismiss per steps 1–4. |
| 8 | Few locations (≤7) | Configure 3–7 locations. | All rows visible without scrolling. |
| 9 | Many locations (>7) | Configure 8+ locations. | List scrolls; exactly 7 rows visible; open/dismiss per steps 1–4. |
| 10 | Menu bar-only mode | Settings → General → enable menu bar-only mode; Dock icon disappears. | Steps 1–4 all pass in accessory mode. |
| 11 | Dock (regular) mode | Disable menu bar-only mode. | Main window and popup coexist; dismissing the popup never closes the main window. |
| 12 | Background forecast refresh | Open the popup and wait ≥30 s (or trigger Refresh All). | Row spinners/staleness update in place; popup stays open; label updates don't dismiss it. |
| 13 | Change selected location | Click a row. | Main window opens with that location selected; popup closes intentionally. |
| 14 | Open Settings | Click "Settings…". | Settings window opens; popup closes; app keeps running. |
| 15 | Open main window | Click "Open SunsetHue…". | Main window opens and activates; popup closes; app keeps running. |
| 16 | Location rotation | Settings → Menu Bar → rotate mode, 5 s interval; open popup. | Popup stays open while the status-item label rotates behind it. |
