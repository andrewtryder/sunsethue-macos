#!/usr/bin/env bash
# Build an unsigned SunsetHue.dmg for free GitHub Releases (no Apple Developer account).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

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

xcodebuild \
  -scheme SunsetHue \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED}" \
  -configuration Release \
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

# xcodebuild registers the product with Launch Services / PluginKit. An ad-hoc
# unsigned .app poisons desktop widgets while developing a signed Debug build.
unregister_app() {
  local app="$1"
  local appex="${app}/Contents/PlugIns/SunsetHueWidget.appex"
  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [[ -d "${appex}" ]]; then
    pluginkit -r "${appex}" >/dev/null 2>&1 || true
  fi
  if [[ -d "${app}" && -x "${lsregister}" ]]; then
    "${lsregister}" -u "${app}" >/dev/null 2>&1 || true
  fi
}
unregister_app "${APP_PATH}"

# Stage app + first-run readme, then assemble DMG root (drag-to-install).
STAGE="${DIST}/stage"
DMG_ROOT="${DIST}/dmg-root"
rm -rf "${STAGE}" "${DMG_ROOT}"
mkdir -p "${STAGE}" "${DMG_ROOT}"
ditto "${APP_PATH}" "${STAGE}/${APP_NAME}.app"
unregister_app "${STAGE}/${APP_NAME}.app"

cat > "${STAGE}/README-FIRST.txt" <<EOF
SunsetHue for macOS (unsigned build)

This build is distributed free on GitHub without Apple notarization.

Install from the DMG:
1. Drag SunsetHue.app to Applications
2. Right-click SunsetHue.app → Open → Open
   (or remove quarantine: xattr -dr com.apple.quarantine /Applications/SunsetHue.app)
3. Add your SunsetHue API key and a location in the app.

Notes:
- Settings/cache live in ~/Library/Application Support/SunsetHue/
- The API key is stored in your login Keychain only
- Desktop widgets require a signed Personal Team build from Xcode (not this unsigned DMG)
- Unofficial; not affiliated with SunsetHue or Apple
EOF

ditto "${STAGE}/${APP_NAME}.app" "${DMG_ROOT}/${APP_NAME}.app"
cp "${STAGE}/README-FIRST.txt" "${DMG_ROOT}/README-FIRST.txt"
ln -s /Applications "${DMG_ROOT}/Applications"
unregister_app "${DMG_ROOT}/${APP_NAME}.app"

DMG_VERSIONED="${DIST}/${APP_NAME}-${VERSION}-macos-unsigned.dmg"
DMG_STABLE="${DIST}/${APP_NAME}-macos-unsigned.dmg"
rm -f "${DMG_VERSIONED}" "${DMG_STABLE}"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_ROOT}" \
  -ov \
  -format UDZO \
  "${DMG_VERSIONED}"
cp -f "${DMG_VERSIONED}" "${DMG_STABLE}"

# Keep only archives on disk so Spotlight / PluginKit do not rediscover the
# unsigned .app next to a signed Xcode Debug build.
rm -rf "${STAGE}" "${DMG_ROOT}"
unregister_app "${APP_PATH}"

echo "Created ${DMG_VERSIONED}"
echo "Created ${DMG_STABLE}"
ls -lh "${DMG_VERSIONED}" "${DMG_STABLE}"
echo "Note: unsigned .app was unregistered from Launch Services (widgets need a signed Xcode Debug run)."
