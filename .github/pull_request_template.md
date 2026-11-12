## Pull Request Checklist

### Pre-Merge Invariants
- [ ] Swift package tests pass locally: `swift test --package-path .`
- [ ] No required signing identity or provisioning profiles introduced (`CODE_SIGNING_ALLOWED=NO`)
- [ ] Unsigned distribution workflow preserved (`./scripts/package-unsigned.sh` succeeds)
- [ ] Desktop widget extension stripped from standard unsigned DMG (`verify_widget_absent`)
- [ ] Version metadata consistent across manifests: `python3 scripts/verify_release_metadata.py`
- [ ] Xcode project synchronized if `project.yml` modified: `xcodegen generate && git diff --exit-code -- SunsetHue.xcodeproj`
- [ ] No secrets, keys, or private coordinates committed

### Changes Description
<!-- Summary of changes made and purpose -->

### Issue / Feature Reference
<!-- Closes #123 / Relates to ... -->
