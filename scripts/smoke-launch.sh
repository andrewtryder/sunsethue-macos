#!/usr/bin/env bash
# Launch the unsigned Release app once with an isolated Application Support path.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-${ROOT}/build/DerivedData/Build/Products/Release/SunsetHue.app}"

if [[ ! -d "${APP}" ]]; then
  echo "App not found at ${APP}" >&2
  echo "Build Release first (see scripts/package-unsigned.sh)." >&2
  exit 2
fi

TMP="$(mktemp -d /tmp/sunsethue-smoke.XXXXXX)"
trap 'rm -rf "${TMP}"' EXIT

export HOME="${TMP}/home"
mkdir -p "${HOME}/Library/Application Support"
# Brief launch then terminate — confirms the binary starts outside the debugger.
open -na "${APP}" --args -NSDocumentRevisionsDebugMode YES || true
sleep 3
pkill -f "${APP}/Contents/MacOS/SunsetHue" >/dev/null 2>&1 || true
echo "Smoke launch completed for ${APP}"
