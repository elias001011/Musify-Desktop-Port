# Desktop Port Maintenance

This repository is intentionally maintained as a downstream desktop port of
`gokadzev/Musify`.

## Automated Flow

When GitHub Actions is available:

1. `Sync Upstream Release` runs every six hours and can also be started manually.
2. It reads the latest upstream release tag from `gokadzev/Musify`.
3. If this repository already has a matching, non-draft `desktop-v<version>`
   release with all expected desktop assets, it exits without changes.
4. If the desktop release does not exist, it fetches upstream tags and merges the
   upstream release tag into `master`. If the release exists but is incomplete,
   the workflow continues so the release can be repaired.
5. It runs `update.sh`, `flutter pub get`, and `flutter analyze`.
6. It verifies that `pubspec.yaml` matches the expected `desktop-v<version>` tag.
7. It runs a Linux release build as a desktop smoke test before pushing `master`.
8. If the sync is clean, it pushes `master` and dispatches `Build Desktop Release`.
9. `Build Desktop Release` validates the requested release tag before starting
   expensive builds, then builds Linux and Windows packages and publishes a
   stable GitHub release.

`Build Desktop Release` also refuses to publish a manual release when the
requested `desktop-v<version>` tag does not match `pubspec.yaml`.

If cloud sync should be enabled in release builds, configure the repository
variable `MUSIFY_CLOUD_SYNC_URL` with the HTTPS endpoint of the sync backend.
When the variable is empty, the app builds normally and the optional sync UI
shows that no backend is configured.

If the upstream merge, version validation, analysis, or Linux smoke build fails,
the sync workflow opens an issue with a link to the failed run.

## Manual Sync

Use this when Actions is unavailable or a conflict needs local attention:

```bash
git checkout master
git fetch upstream --tags --prune
git merge --no-edit refs/tags/<upstream-version>
./update.sh
flutter pub get
flutter analyze
flutter build linux --release --dart-define=MUSIFY_CLOUD_SYNC_URL=<sync-endpoint>
git push origin master
```

Then create a desktop release:

```bash
gh workflow run desktop_release.yml --ref master -f tag=desktop-v<version> -f prerelease=false
```

If Actions is still blocked, build Linux locally and use a Windows machine for
the Windows assets, then upload the files manually:

```bash
flutter build linux --release
.github/scripts/package_linux_desktop.sh
gh release create desktop-v<version> build/desktop-artifacts/* --latest
```

## Remotes

Recommended local remotes:

```bash
git remote add origin https://github.com/elias001011/Musify-Desktop-Port.git
git remote add upstream https://github.com/gokadzev/Musify.git
```

The original upstream project should remain the source of application updates.
Desktop-only changes should stay small and easy to carry forward.
