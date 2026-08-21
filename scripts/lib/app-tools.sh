#!/usr/bin/env bash
# Shared helper functions for SunsetHue application scripts.
set -euo pipefail

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Unregister an app bundle and any embedded widget from LaunchServices / PluginKit.
unregister_sunsethue_app() {
  local app="$1"
  local appex="${app}/Contents/PlugIns/SunsetHueWidget.appex"

  if [[ -d "${appex}" ]]; then
    pluginkit -r "${appex}" >/dev/null 2>&1 || true
  fi

  if [[ -d "${app}" && -x "${LSREGISTER}" ]]; then
    "${LSREGISTER}" -u "${app}" >/dev/null 2>&1 || true
  fi
}

# Strip SunsetHueWidget.appex from an app bundle and clean empty PlugIns directory.
strip_widget_extension() {
  local app="$1"
  local plugins="${app}/Contents/PlugIns"
  local appex="${plugins}/SunsetHueWidget.appex"

  if [[ -d "${appex}" ]]; then
    pluginkit -r "${appex}" >/dev/null 2>&1 || true
    rm -rf "${appex}"
  fi

  if [[ -d "${plugins}" ]] && [[ -z "$(ls -A "${plugins}" 2>/dev/null || true)" ]]; then
    rmdir "${plugins}" 2>/dev/null || true
  fi
}

# Verify that no widget extension exists inside the app bundle.
verify_widget_absent() {
  local app="$1"
  local appex="${app}/Contents/PlugIns/SunsetHueWidget.appex"

  if [[ -d "${appex}" ]]; then
    echo "Error: SunsetHueWidget.appex is present in unsigned bundle: ${app}" >&2
    exit 1
  fi
}

# Verify that a binary is universal (contains arm64 and x86_64).
verify_universal_binary() {
  local binary="$1"
  local label="${2:-Binary}"
  local archs

  if [[ ! -f "${binary}" ]]; then
    echo "Error: ${label} not found at ${binary}" >&2
    exit 1
  fi

  archs="$(lipo -archs "${binary}")"
  if [[ "${archs}" != "x86_64 arm64" && "${archs}" != "arm64 x86_64" ]]; then
    echo "Error: ${label} is not universal (got: ${archs}, expected arm64 and x86_64)" >&2
    exit 1
  fi
  echo "${label} architectures: ${archs}"
}
