# Release Policy & GitHub Releases Automation

## Mandatory Release Workflow
After completing any feature implementation, bug fix, or user task:
1. **Always Build & Create GitHub Release**: Do not wait for the user to ask "github release". Perform the release automatically at the conclusion of every major feature or fix.
2. **Version Bump**: Increment the version in `pubspec.yaml` (e.g. `version: X.Y.Z+build`).
3. **Build Release APK**:
   ```bash
   flutter build apk --release
   cp build/app/outputs/flutter-apk/app-release.apk nivara-v<VERSION>.apk
   ```
4. **Git Commit & Push**:
   ```bash
   git add .
   git commit -m "<type>(<scope>): <summary> (v<VERSION>)"
   git push origin main
   git tag v<VERSION>
   git push origin v<VERSION>
   ```
5. **Publish GitHub Release**:
   ```bash
   gh release create v<VERSION> nivara-v<VERSION>.apk --title "v<VERSION> - <Title>" --notes "<Detailed Release Notes>"
   ```
6. **Release Retention Rule**:
   - **KEEP ONLY `v1.0.55` and the LATEST VERSION** on GitHub releases.
   - Delete all other intermediate or older releases from GitHub (`gh release delete <tag> --yes --cleanup-tag`).
   - Confirm via `gh release list` that only `v1.0.55` and the newest release remain.
