#!/usr/bin/env bash
# Build an unsigned universal SunsetHue.dmg for GitHub Releases (no Apple Developer account).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Source shared app tools
source "${ROOT}/scripts/lib/app-tools.sh"

DERIVED="${ROOT}/build/DerivedData"
DIST="${ROOT}/dist"
APP_NAME="SunsetHue"
VERSION="$(sed -n 's/^MARKETING_VERSION *= *\([0-9.]*\).*/\1/p' Config/Version.xcconfig | head -1 | tr -d '[:space:]')"
if [[ -z "${VERSION}" ]]; then
  VERSION="1.0.0"
fi

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi

rm -rf "${DERIVED}" "${DIST}"
mkdir -p "${DIST}"

echo "Building unsigned Release (${APP_NAME} ${VERSION}, universal arm64 + x86_64)…"
xcodebuild \
  -scheme "${APP_NAME}" \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED}" \
  -configuration Release \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=- \
  build

APP_PATH="${DERIVED}/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "${APP_PATH}" ]]; then
  # Fall back to Debug products if Release folder naming differs.
  APP_PATH="${DERIVED}/Build/Products/Debug/${APP_NAME}.app"
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Built app not found under ${DERIVED}/Build/Products" >&2
  exit 1
fi

# Verify universal executable
verify_universal_binary "${APP_PATH}/Contents/MacOS/${APP_NAME}" "${APP_NAME}"

# Strip widget extension from unsigned distribution
unregister_sunsethue_app "${APP_PATH}"
strip_widget_extension "${APP_PATH}"
verify_widget_absent "${APP_PATH}"

# Stage app + first-run readme, then assemble DMG root (drag-to-install).
STAGE="${DIST}/stage"
DMG_ROOT="${DIST}/dmg-root"
rm -rf "${STAGE}" "${DMG_ROOT}"
mkdir -p "${STAGE}" "${DMG_ROOT}"
ditto "${APP_PATH}" "${STAGE}/${APP_NAME}.app"
unregister_sunsethue_app "${STAGE}/${APP_NAME}.app"
strip_widget_extension "${STAGE}/${APP_NAME}.app"
verify_widget_absent "${STAGE}/${APP_NAME}.app"

cat > "${STAGE}/README-FIRST.txt" <<EOF
SunsetHue for macOS

1. Drag SunsetHue.app to Applications.
2. On first launch, right-click SunsetHue → Open.
   If blocked, use System Settings → Privacy & Security → Open Anyway.
3. Add your SunsetHue API key in Settings → Account.
4. Add at least one location.

This is an unsigned, unnotarized build distributed from the project's
official GitHub Releases page.

No Apple Developer account or Xcode is required.

Desktop widgets are not included in this build.

API keys are stored in macOS Keychain.
EOF

ditto "${STAGE}/${APP_NAME}.app" "${DMG_ROOT}/${APP_NAME}.app"
cp "${STAGE}/README-FIRST.txt" "${DMG_ROOT}/README-FIRST.txt"
ln -s /Applications "${DMG_ROOT}/Applications"
unregister_sunsethue_app "${DMG_ROOT}/${APP_NAME}.app"

DMG_VERSIONED="${DIST}/${APP_NAME}-${VERSION}-macos-unsigned.dmg"
DMG_STABLE="${DIST}/${APP_NAME}-macos-unsigned.dmg"
rm -f "${DMG_VERSIONED}" "${DMG_STABLE}"

echo "Creating DMG image…"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_ROOT}" \
  -ov \
  -format UDZO \
  "${DMG_VERSIONED}"
cp -f "${DMG_VERSIONED}" "${DMG_STABLE}"

# Clean up stage and dmg-root temporary directories
rm -rf "${STAGE}" "${DMG_ROOT}"
unregister_sunsethue_app "${APP_PATH}"

echo
echo "Created: ${DMG_VERSIONED}"
echo "Created: ${DMG_STABLE}"
ls -lh "${DMG_VERSIONED}" "${DMG_STABLE}"
