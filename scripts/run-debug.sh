#!/usr/bin/env bash
# Build and launch the unsigned SunsetHue app for local development.
# No Apple Developer account, signing identity, or WidgetKit extension required.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${ROOT}/build/DerivedData-debug-unsigned"
APP_NAME="SunsetHue"
APP="${DERIVED}/Build/Products/Debug/${APP_NAME}.app"
INSTALL_TO_APPLICATIONS="${INSTALL_TO_APPLICATIONS:-1}"

# Source shared app tools
source "${ROOT}/scripts/lib/app-tools.sh"

cd "${ROOT}"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi

echo "Building unsigned Debug (${APP_NAME})…"
xcodebuild \
  -scheme "${APP_NAME}" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=- \
  build

if [[ ! -d "${APP}" ]]; then
  echo "Debug app not found at ${APP}" >&2
  exit 1
fi

# Unregister and strip the widget extension for unsigned development
unregister_sunsethue_app "${APP}"
strip_widget_extension "${APP}"
verify_widget_absent "${APP}"

# Terminate existing instance before replacing/relaunching
pkill -x "${APP_NAME}" 2>/dev/null || true
pkill -f 'SunsetHueWidget.appex' 2>/dev/null || true
sleep 1

FINAL_APP="${APP}"

if [[ "${INSTALL_TO_APPLICATIONS}" == "1" ]]; then
  TARGET_APP="/Applications/${APP_NAME}.app"
  echo "Installing unsigned Debug build to ${TARGET_APP}…"
  unregister_sunsethue_app "${TARGET_APP}"
  rm -rf "${TARGET_APP}"
  ditto "${APP}" "${TARGET_APP}"
  strip_widget_extension "${TARGET_APP}"
  verify_widget_absent "${TARGET_APP}"
  FINAL_APP="${TARGET_APP}"
fi

open -na "${FINAL_APP}"

echo
echo "Build mode: unsigned Debug"
echo "Widget: excluded"
echo "Storage: ~/Library/Application Support/SunsetHue/"
echo "App: ${FINAL_APP}"
