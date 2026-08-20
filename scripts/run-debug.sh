#!/usr/bin/env bash
# Build a signed Debug app, register its WidgetKit extension, and launch it.
# Use this for local widget development (Personal Team). Avoids stale
# /Applications or unsigned DerivedData copies poisoning PluginKit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${ROOT}/build/DerivedData-signed"
APP="${DERIVED}/Build/Products/Debug/SunsetHue.app"
APPEX="${APP}/Contents/PlugIns/SunsetHueWidget.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
INSTALL_TO_APPLICATIONS="${INSTALL_TO_APPLICATIONS:-1}"

cd "${ROOT}"

if [[ ! -f Config/Local.xcconfig ]]; then
  echo "Missing Config/Local.xcconfig (needed for Personal Team signing)." >&2
  echo "  cp Config/Local.xcconfig.example Config/Local.xcconfig" >&2
  echo "  # then set DEVELOPMENT_TEAM" >&2
  exit 2
fi

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi

echo "Building signed Debug…"
xcodebuild \
  -scheme SunsetHue \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED}" \
  -allowProvisioningUpdates \
  build

if [[ ! -d "${APP}" ]]; then
  echo "Debug app not found at ${APP}" >&2
  exit 2
fi

pkill -x SunsetHue 2>/dev/null || true
pkill -f 'SunsetHueWidget.appex' 2>/dev/null || true
sleep 1

# Drop stale hosts that hide the Debug appex from Edit Widgets.
if [[ -d /Applications/SunsetHue.app && "$(realpath /Applications/SunsetHue.app 2>/dev/null || true)" != "$(realpath "${APP}")" ]]; then
  pluginkit -r "/Applications/SunsetHue.app/Contents/PlugIns/SunsetHueWidget.appex" >/dev/null 2>&1 || true
  "${LSREGISTER}" -u "/Applications/SunsetHue.app" >/dev/null 2>&1 || true
fi
OTHER="${ROOT}/build/DerivedData/Build/Products/Debug/SunsetHue.app"
if [[ -d "${OTHER}" ]]; then
  pluginkit -r "${OTHER}/Contents/PlugIns/SunsetHueWidget.appex" >/dev/null 2>&1 || true
  "${LSREGISTER}" -u "${OTHER}" >/dev/null 2>&1 || true
fi

if [[ "${INSTALL_TO_APPLICATIONS}" == "1" ]]; then
  echo "Installing signed Debug build to /Applications/SunsetHue.app (gallery discovery)…"
  rm -rf /Applications/SunsetHue.app
  ditto "${APP}" /Applications/SunsetHue.app
  APP="/Applications/SunsetHue.app"
  APPEX="${APP}/Contents/PlugIns/SunsetHueWidget.appex"
fi

killall chronod 2>/dev/null || true
sleep 1

"${LSREGISTER}" -f "${APP}"
pluginkit -a "${APPEX}" >/dev/null 2>&1 || true
pluginkit -e use -i com.andrewtryder.SunsetHue.Widget >/dev/null 2>&1 || true

echo "PluginKit:"
pluginkit -mv -i com.andrewtryder.SunsetHue.Widget || true

open -na "${APP}"
echo
echo "Launched: ${APP}"
echo "Next: remove any old SunsetHue widgets, then Edit Widgets → add SunsetHue."
