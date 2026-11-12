#!/usr/bin/env bash
# Build and launch the unsigned SunsetHue app for local development.
# No Apple Developer account, signing identity, or WidgetKit extension required.
#
# Default: runs the app directly from build/DerivedData-debug-unsigned. Nothing
# in /Applications is touched and any installed SunsetHue keeps running.
#
# Installing to /Applications (needed only to test notifications, which macOS
# attributes to an app in a stable location) is opt-in:
#   ./scripts/run-debug.sh --install          # asks for confirmation
#   ./scripts/run-debug.sh --install --yes    # non-interactive
#   INSTALL_TO_APPLICATIONS=1 ./scripts/run-debug.sh   # same as --install
# User data in ~/Library/Application Support/SunsetHue and Keychain items are
# never modified by this script.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${ROOT}/build/DerivedData-debug-unsigned"
APP_NAME="SunsetHue"
APP="${DERIVED}/Build/Products/Debug/${APP_NAME}.app"
INSTALL_TO_APPLICATIONS="${INSTALL_TO_APPLICATIONS:-0}"
ALLOW_CONCURRENT="${ALLOW_CONCURRENT:-0}"
ASSUME_YES=0

for arg in "$@"; do
  case "${arg}" in
    --install) INSTALL_TO_APPLICATIONS=1 ;;
    --allow-concurrent) ALLOW_CONCURRENT=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Unknown option: ${arg}" >&2; exit 2 ;;
  esac
done

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

# Check if an installed copy is already running. Both copies share the same
# Application Support and Keychain items; concurrent execution can cause write races.
TARGET_APP="/Applications/${APP_NAME}.app"
installed_pids=""
for pid in $(pgrep -x "${APP_NAME}" 2>/dev/null || true); do
  if ps -p "${pid}" -o command= 2>/dev/null | grep -q "${TARGET_APP}"; then
    installed_pids="${installed_pids} ${pid}"
  fi
done

if [[ -n "${installed_pids}" && "${INSTALL_TO_APPLICATIONS}" != "1" && "${ALLOW_CONCURRENT}" != "1" ]]; then
  echo "⚠️  An installed instance of ${APP_NAME} (${TARGET_APP}) is currently running (PID:${installed_pids})." >&2
  echo "Running both simultaneously can cause storage and scheduling conflicts." >&2
  echo "Options:" >&2
  echo "  1) Quit the installed app and re-run this script" >&2
  echo "  2) Run with --allow-concurrent to bypass this check" >&2
  echo "  3) Run with --install to replace the installed app" >&2
  exit 1
fi

# Stop only a previous instance launched from the development output directory.
stop_dev_instance() {
  local pid
  for pid in $(pgrep -x "${APP_NAME}" 2>/dev/null || true); do
    if ps -p "${pid}" -o command= 2>/dev/null | grep -q "${DERIVED}"; then
      kill "${pid}" 2>/dev/null || true
    fi
  done
}
stop_dev_instance
sleep 1

FINAL_APP="${APP}"

if [[ "${INSTALL_TO_APPLICATIONS}" == "1" ]]; then
  TARGET_APP="/Applications/${APP_NAME}.app"
  if [[ -d "${TARGET_APP}" ]]; then
    echo "This will REPLACE the existing ${TARGET_APP} with an unsigned Debug build."
  else
    echo "This will install an unsigned Debug build to ${TARGET_APP}."
  fi
  if [[ "${ASSUME_YES}" != "1" ]]; then
    if [[ ! -t 0 ]]; then
      echo "Refusing to install without confirmation (not a terminal). Pass --yes to confirm." >&2
      exit 1
    fi
    read -r -p "Continue? [y/N] " reply
    [[ "${reply}" =~ ^[Yy]$ ]] || { echo "Aborted; nothing installed."; exit 1; }
  fi
  # Quit only the installed copy being replaced.
  for pid in $(pgrep -x "${APP_NAME}" 2>/dev/null || true); do
    if ps -p "${pid}" -o command= 2>/dev/null | grep -q "${TARGET_APP}"; then
      kill "${pid}" 2>/dev/null || true
    fi
  done
  sleep 1
  echo "Installing unsigned Debug build to ${TARGET_APP}…"
  unregister_sunsethue_app "${TARGET_APP}"
  rm -rf "${TARGET_APP}"
  ditto "${APP}" "${TARGET_APP}"
  strip_widget_extension "${TARGET_APP}"
  verify_widget_absent "${TARGET_APP}"
  FINAL_APP="${TARGET_APP}"
fi

open -n "${FINAL_APP}"

echo
echo "Build mode: unsigned Debug"
echo "Widget: excluded"
echo "Storage: ~/Library/Application Support/SunsetHue/"
echo "App: ${FINAL_APP}"
