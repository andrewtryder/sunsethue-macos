#!/usr/bin/env python3
"""Verify that app version declarations stay in sync (semver X.Y.Z)."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
MARKETING_XCCONFIG_RE = re.compile(
    r"^MARKETING_VERSION\s*=\s*([0-9]+\.[0-9]+\.[0-9]+)\s*(?://.*)?$",
    re.MULTILINE,
)
MARKETING_YML_RE = re.compile(
    r'^[\t ]*MARKETING_VERSION:\s*"([0-9]+\.[0-9]+\.[0-9]+)"\s*(?:#.*)?$',
    re.MULTILINE,
)
MARKETING_SWIFT_RE = re.compile(
    r'public static let marketingVersion = "([0-9]+\.[0-9]+\.[0-9]+)"\s*(?://.*)?',
)


class VersionError(ValueError):
    pass


def read_versions(root: Path) -> dict[str, str]:
    xcconfig = (root / "Config/Version.xcconfig").read_text(encoding="utf-8")
    yml = (root / "project.yml").read_text(encoding="utf-8")
    constants = (root / "Sources/SunsetHueCore/Constants.swift").read_text(encoding="utf-8")
    manifest = json.loads((root / ".release-please-manifest.json").read_text(encoding="utf-8"))

    versions = {
        "Config/Version.xcconfig": _match(MARKETING_XCCONFIG_RE, xcconfig, "Version.xcconfig"),
        "project.yml": _match(MARKETING_YML_RE, yml, "project.yml"),
        "Constants.swift": _match(MARKETING_SWIFT_RE, constants, "Constants.swift"),
        ".release-please-manifest.json": _string(manifest.get("."), "manifest"),
    }
    return versions


def _match(pattern: re.Pattern[str], text: str, label: str) -> str:
    match = pattern.search(text)
    if not match:
        raise VersionError(f"Version not found in {label}")
    return _string(match.group(1), label)


def _string(value: object, label: str) -> str:
    if not isinstance(value, str) or not VERSION_RE.fullmatch(value):
        raise VersionError(f"Invalid version in {label}: {value!r}")
    return value


def verify(root: Path, expected: str | None = None) -> str:
    versions = read_versions(root)
    unique = set(versions.values())
    if len(unique) != 1:
        raise VersionError(f"Version declarations differ: {versions}")
    version = unique.pop()
    if expected is not None and version != expected:
        raise VersionError(f"Expected {expected!r}, found {version!r} ({versions})")
    return version


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--expected-version")
    args = parser.parse_args(argv)
    try:
        version = verify(args.root, args.expected_version)
    except VersionError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1
    print(version)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
