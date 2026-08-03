#!/usr/bin/env bash
# Launch the unsigned Release app once with an isolated Application Support path.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-${ROOT}/build/DerivedData/Build/Products/Release/SunsetHue.app}"
ALIVE_SECONDS="${SMOKE_ALIVE_SECONDS:-3}"

if [[ ! -d "${APP}" ]]; then
  echo "App not found at ${APP}" >&2
  echo "Build Release first (see scripts/package-unsigned.sh)." >&2
  exit 2
fi

BINARY="${APP}/Contents/MacOS/SunsetHue"
if [[ ! -x "${BINARY}" ]]; then
  echo "Executable not found at ${BINARY}" >&2
  exit 2
fi

TMP="$(mktemp -d /tmp/sunsethue-smoke.XXXXXX)"
cleanup() {
  if [[ -n "${PID:-}" ]] && kill -0 "${PID}" 2>/dev/null; then
    kill "${PID}" 2>/dev/null || true
    wait "${PID}" 2>/dev/null || true
  fi
  rm -rf "${TMP}"
}
trap cleanup EXIT

export HOME="${TMP}/home"
mkdir -p "${HOME}/Library/Application Support"

# Launch directly so we own the PID (avoid open || true success-on-failure).
"${BINARY}" >/tmp/sunsethue-smoke-stdout.log 2>/tmp/sunsethue-smoke-stderr.log &
PID=$!

if ! kill -0 "${PID}" 2>/dev/null; then
  echo "Smoke launch failed: process exited immediately" >&2
  cat /tmp/sunsethue-smoke-stderr.log >&2 || true
  exit 1
fi

sleep "${ALIVE_SECONDS}"

if ! kill -0 "${PID}" 2>/dev/null; then
  echo "Smoke launch failed: process died within ${ALIVE_SECONDS}s (pid ${PID})" >&2
  cat /tmp/sunsethue-smoke-stderr.log >&2 || true
  log show --predicate "processID == ${PID} OR processImagePath CONTAINS \"SunsetHue\"" --last 2m 2>/dev/null | tail -n 80 >&2 || true
  exit 1
fi

kill "${PID}" 2>/dev/null || true
wait "${PID}" 2>/dev/null || true
PID=""
echo "Smoke launch completed for ${APP} (survived ${ALIVE_SECONDS}s)"
