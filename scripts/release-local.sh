#!/usr/bin/env bash
# Build, validate, package, and upload an unsigned SunsetHue release from macOS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

# Source shared app tools
source "${ROOT}/scripts/lib/app-tools.sh"

DRY_RUN="${DRY_RUN:-0}"
FULL_VALIDATION="${FULL_VALIDATION:-0}"
RAW_ARG=""

for arg in "$@"; do
  case "${arg}" in
    --dry-run)
      DRY_RUN=1
      ;;
    --full-validation)
      FULL_VALIDATION=1
      ;;
    *)
      if [[ -z "${RAW_ARG}" ]]; then
        RAW_ARG="${arg}"
      else
        echo "Error: unexpected extra argument '${arg}'" >&2
        echo "Usage: $0 [--dry-run] [--full-validation] <version>" >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "${RAW_ARG}" ]]; then
  # Fall back to Version.xcconfig if no argument provided
  VERSION="$(sed -n 's/^MARKETING_VERSION *= *\([0-9.]*\).*/\1/p' Config/Version.xcconfig | head -1 | tr -d '[:space:]')"
else
  VERSION="${RAW_ARG#v}"
fi

TAG="v${VERSION}"

echo "============================================================"
echo "SunsetHue Local Release: ${TAG} (version ${VERSION})"
if [[ "${DRY_RUN}" == "1" ]]; then
  echo "Mode: DRY RUN (upload will be skipped)"
fi
echo "============================================================"

# A. Preconditions
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: release-local.sh must run on macOS (Darwin)." >&2
  exit 1
fi

REQUIRED_TOOLS=(xcodebuild xcrun git gh hdiutil lipo xcodegen shasum python3)
for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "Error: required tool '${tool}' is not installed or not in PATH." >&2
    exit 1
  fi
done

if [[ "${DRY_RUN}" == "0" ]]; then
  if ! gh auth status >/dev/null 2>&1; then
    echo "Error: GitHub CLI is not authenticated. Run 'gh auth login' before releasing." >&2
    exit 1
  fi
fi

# Require clean git working tree (allow untracked build/dist which are ignored, and SunsetHue.xcodeproj which is regenerated)
if ! git diff --quiet -- ':!SunsetHue.xcodeproj' ':!scripts/release-local.sh' || ! git diff --cached --quiet; then
  if [[ "${DRY_RUN}" == "0" ]]; then
    echo "Error: git working tree has unstaged or staged changes. Please commit or stash before releasing." >&2
    git status --short >&2
    exit 1
  else
    echo "Note [dry-run]: git working tree has uncommitted changes. Continuing dry-run validation."
  fi
fi

CURRENT_BRANCH="$(git branch --show-current 2>/dev/null || true)"
if [[ "${CURRENT_BRANCH}" != "main" && "${DRY_RUN}" == "0" ]]; then
  echo "Error: release-local.sh must be run on the 'main' branch (current: '${CURRENT_BRANCH}')." >&2
  exit 1
fi

echo "Fetching remote origin and tags…"
git fetch origin main --tags >/dev/null 2>&1 || true

# B. Version and Tag Validation
echo "Validating release version metadata…"
python3 scripts/verify_release_metadata.py --expected-version "${VERSION}"

LOCAL_TAG_EXISTS=0
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
  LOCAL_TAG_EXISTS=1
fi

REMOTE_TAG_EXISTS=0
if git ls-remote --tags origin "refs/tags/${TAG}" | grep -q "${TAG}"; then
  REMOTE_TAG_EXISTS=1
fi

if [[ "${DRY_RUN}" == "0" ]]; then
  if [[ "${LOCAL_TAG_EXISTS}" != "1" ]]; then
    echo "Error: local tag '${TAG}' does not exist. Ensure Release Please has created the tag." >&2
    exit 1
  fi
  if [[ "${REMOTE_TAG_EXISTS}" != "1" ]]; then
    echo "Error: remote tag '${TAG}' does not exist on origin." >&2
    exit 1
  fi

  TAG_COMMIT="$(git rev-parse "${TAG}^{commit}")"
  HEAD_COMMIT="$(git rev-parse HEAD)"
  if [[ "${TAG_COMMIT}" != "${HEAD_COMMIT}" ]]; then
    echo "Error: HEAD (${HEAD_COMMIT}) does not point to tag ${TAG} (${TAG_COMMIT})." >&2
    exit 1
  fi
else
  if [[ "${LOCAL_TAG_EXISTS}" != "1" || "${REMOTE_TAG_EXISTS}" != "1" ]]; then
    echo "Note [dry-run]: tag '${TAG}' not found locally/remotely. Continuing dry-run validation."
  fi
fi

# C. GitHub Release Validation
if [[ "${DRY_RUN}" == "0" ]]; then
  if ! gh release view "${TAG}" >/dev/null 2>&1; then
    echo "Error: GitHub Release '${TAG}' was not found on GitHub." >&2
    echo "Expected workflow: Release Please creates the GitHub Release when the release PR is merged." >&2
    exit 1
  fi
fi

# D. Validation before packaging
echo "Running standard unit tests…"
swift test --package-path .

if [[ "${FULL_VALIDATION}" == "1" ]]; then
  echo "Running Thread Sanitizer (TSan) suite…"
  swift test --package-path . --sanitize=thread
  echo "Running Address Sanitizer (ASan) suite…"
  swift test --package-path . --sanitize=address
fi

echo "Verifying Xcode project generation…"
xcodegen generate

# E. Packaging
echo "Building and packaging universal unsigned DMG…"
./scripts/package-unsigned.sh

# F. Verify artifacts
VERSIONED_DMG="${ROOT}/dist/SunsetHue-${VERSION}-macos-unsigned.dmg"
STABLE_DMG="${ROOT}/dist/SunsetHue-macos-unsigned.dmg"

if [[ ! -f "${VERSIONED_DMG}" ]]; then
  echo "Error: versioned DMG not found at ${VERSIONED_DMG}" >&2
  exit 1
fi

echo "Verifying DMG contents non-interactively…"
MOUNT_DIR="$(mktemp -d /tmp/sunsethue-dmg-mount.XXXXXX)"
cleanup_mount() {
  if mount | grep -q "${MOUNT_DIR}"; then
    hdiutil detach "${MOUNT_DIR}" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "${MOUNT_DIR}"
}
trap cleanup_mount EXIT

hdiutil attach -nobrowse -readonly "${VERSIONED_DMG}" -mountpoint "${MOUNT_DIR}" -quiet

MOUNTED_APP="${MOUNT_DIR}/SunsetHue.app"
if [[ ! -d "${MOUNTED_APP}" ]]; then
  echo "Error: SunsetHue.app not found inside DMG at ${MOUNTED_APP}" >&2
  exit 1
fi

verify_universal_binary "${MOUNTED_APP}/Contents/MacOS/SunsetHue" "Packaged App"
verify_widget_absent "${MOUNTED_APP}"

hdiutil detach "${MOUNT_DIR}" -quiet
rm -rf "${MOUNT_DIR}"
trap - EXIT

# G. Checksums
echo "Generating SHA256 checksum…"
(
  cd "${ROOT}/dist"
  shasum -a 256 "SunsetHue-${VERSION}-macos-unsigned.dmg" > "SunsetHue-${VERSION}-macos-unsigned.dmg.sha256"
)
CHECKSUM_FILE="${ROOT}/dist/SunsetHue-${VERSION}-macos-unsigned.dmg.sha256"
CHECKSUM_VAL="$(awk '{print $1}' "${CHECKSUM_FILE}")"

# H. Upload
if [[ "${DRY_RUN}" == "1" ]]; then
  echo "Dry-run mode: skipping asset upload to GitHub Release."
  UPLOAD_STATUS="skipped (dry-run)"
else
  echo "Uploading assets to GitHub Release ${TAG}…"
  ASSETS=(
    "${VERSIONED_DMG}"
    "${CHECKSUM_FILE}"
  )
  if [[ -f "${STABLE_DMG}" ]]; then
    ASSETS+=("${STABLE_DMG}")
  fi
  gh release upload "${TAG}" "${ASSETS[@]}" --clobber
  UPLOAD_STATUS="uploaded"
fi

# I. Final report
HEAD_SHA="$(git rev-parse HEAD)"
echo
echo "============================================================"
echo "Release Summary"
echo "============================================================"
echo "Release:        ${TAG}"
echo "Commit:         ${HEAD_SHA}"
echo "Architectures:  arm64 x86_64"
echo "Widget:         excluded"
echo "Versioned DMG:  ${VERSIONED_DMG}"
echo "SHA256:         ${CHECKSUM_VAL}"
echo "GitHub Release: ${UPLOAD_STATUS}"
echo
echo "Next step:"
echo "  gh release view ${TAG} --web"
echo "============================================================"
