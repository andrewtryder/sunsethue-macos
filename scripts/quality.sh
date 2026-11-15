#!/usr/bin/env bash
# Quality gate for SunsetHue: formatting, linting, and tests.
#
# Usage:
#   ./scripts/quality.sh --staged   # check only files staged for commit (default for pre-commit)
#   ./scripts/quality.sh --full     # check every Swift file in the repo (default when run directly)
#   ./scripts/quality.sh --fix      # apply SwiftFormat fixes first, then run the full gate
#
# Checks run:
#   1. swiftformat --lint           (formatting)
#   2. swiftlint --strict           (code quality; warnings fail in strict mode)
#   3. swift test                   (unit tests) — full mode only
#   4. bash -n on scripts/*.sh      (shell syntax) — full mode only
#
# Exit codes: 0 = all checks passed, 1 = at least one check failed,
# 2 = usage error or missing tool.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="full"
FIX=0

for arg in "$@"; do
  case "${arg}" in
    --staged) MODE="staged" ;;
    --full) MODE="full" ;;
    --fix) FIX=1 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "quality.sh: unknown option '${arg}'" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*" >&2; }

for tool in swiftformat swiftlint; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    fail "${tool} is not installed. Install with 'brew install swiftformat' / 'brew install swiftlint'."
    exit 2
  fi
done

# ---------------------------------------------------------------------------
# Fix mode: apply SwiftFormat before checking.
# ---------------------------------------------------------------------------
if [[ "$FIX" -eq 1 ]]; then
  log "swiftformat (applying fixes)"
  swiftformat . || fail "swiftformat failed to run"
fi

# ---------------------------------------------------------------------------
# Determine the file set being checked.
# ---------------------------------------------------------------------------
if [[ "$MODE" == "staged" ]]; then
  SWIFT_FILES="$(git diff --cached --name-only --diff-filter=ACMR -- '*.swift' || true)"
  if [[ -z "$SWIFT_FILES" ]]; then
    log "No staged Swift files; skipping formatting/lint checks."
    exit 0
  fi
  log "Checking $(echo "$SWIFT_FILES" | wc -l | tr -d ' ') staged Swift file(s)"
else
  SWIFT_FILES=""
  log "Checking all Swift sources (full mode)"
fi

FAILED=0

# ---------------------------------------------------------------------------
# 1. SwiftFormat
# ---------------------------------------------------------------------------
log "swiftformat --lint"
if [[ "$MODE" == "staged" ]]; then
  # shellcheck disable=SC2086
  if ! swiftformat --lint $SWIFT_FILES; then
    fail "Formatting violations in staged files. Run './scripts/quality.sh --fix' and re-stage."
    FAILED=1
  fi
else
  if ! swiftformat --lint .; then
    fail "Formatting violations. Run './scripts/quality.sh --fix'."
    FAILED=1
  fi
fi

# ---------------------------------------------------------------------------
# 2. SwiftLint (strict: warnings also fail)
# ---------------------------------------------------------------------------
log "swiftlint --strict"
if [[ "$MODE" == "staged" ]]; then
  # shellcheck disable=SC2086
  if ! swiftlint lint --strict --quiet $SWIFT_FILES; then
    fail "SwiftLint violations in staged files."
    FAILED=1
  fi
else
  if ! swiftlint lint --strict --quiet; then
    fail "SwiftLint violations."
    FAILED=1
  fi
fi

# ---------------------------------------------------------------------------
# 3. Tests + shell syntax (full mode only; staged mode stays fast)
# ---------------------------------------------------------------------------
if [[ "$MODE" == "full" ]]; then
  log "swift test"
  if ! swift test 2>&1 | tail -5; then
    : # swift test prints its own failure summary; tail keeps the log readable
  fi
  TEST_RESULT="${PIPESTATUS[0]}"
  if [[ "$TEST_RESULT" -ne 0 ]]; then
    fail "Unit tests failed."
    FAILED=1
  fi

  log "bash -n (shell syntax)"
  SHELL_SCRIPTS="$(find scripts -name '*.sh' -type f)"
  for sh in $SHELL_SCRIPTS; do
    if ! bash -n "$sh"; then
      fail "Shell syntax error in ${sh}"
      FAILED=1
    fi
  done
fi

if [[ "$FAILED" -ne 0 ]]; then
  fail "Quality gate failed."
  exit 1
fi

log "All quality checks passed."
