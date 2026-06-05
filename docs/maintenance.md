# Desktop Port Maintenance

This repository is intentionally maintained as a downstream desktop port of
`gokadzev/Musify`.

## Automated Flow

When GitHub Actions is available:

1. `Sync Upstream Release` runs every six hours and can also be started manually.
2. It reads the latest upstream release tag from `gokadzev/Musify`.
3. If this repository already has a matching, non-draft `desktop-v<version>`
   release with all expected desktop assets, it exits without changes.
4. If the desktop release does not exist, it fetches only the selected upstream
   release tag and merges it into `refs/heads/master`. If the release exists but
   is incomplete, the workflow continues so the release can be repaired.
5. It runs `update.sh`, `flutter pub get`, and `flutter analyze`.
6. It verifies that `pubspec.yaml` matches the expected `desktop-v<version>` tag.
7. It runs a Linux release build as a desktop smoke test before pushing `master`.
8. If the sync is clean, it pushes `master` and dispatches `Build Desktop Release`.
   If the matching desktop release already existed but was missing assets, it
   dispatches repair mode explicitly.
9. `Build Desktop Release` validates the requested release tag before starting
   expensive builds, then builds Linux and Windows packages and publishes a
   stable GitHub release.

`Build Desktop Release` also refuses to publish a manual release when the
requested tag does not match `pubspec.yaml`. Rebuild-only desktop releases may
use a numeric revision suffix such as `desktop-v10.0.8-2`.

To rebuild or repair assets from an older commit while keeping the current
workflow, pass `source_ref` and explicitly allow repairing the existing release:

```bash
gh workflow run desktop_release.yml \
  --ref refs/heads/master \
  -f tag=desktop-v10.0.8 \
  -f source_ref=<commit-or-tag> \
  -f repair_existing_release=true \
  -f prerelease=false
```

Normal release builds refuse to overwrite an existing GitHub release. This keeps
upstream release syncs append-only: a new upstream release should produce a new
`desktop-v<version>` release, while existing releases are only overwritten during
an explicit repair.

Do not repair an existing release just to ship new app code. If the app code
changed after a published release, publish a numeric revision tag such as
`desktop-v10.0.8-2` so installed apps can compare versions correctly.

If cloud sync should be enabled in release builds, configure the repository
variable `MUSIFY_CLOUD_SYNC_URL` with the HTTPS endpoint of the sync backend.
When the variable is empty, the app builds normally and the optional sync UI
shows that no backend is configured.

If the upstream merge, version validation, analysis, or Linux smoke build fails,
the sync workflow opens an issue with a link to the failed run.

## Branch And Tag Ambiguity

`gokadzev/Musify` contains a historical tag named `master`. If a sync job fetches
all upstream tags, local commands such as `git checkout master` can become
ambiguous because both `refs/heads/master` and `refs/tags/master` exist. The
workflows avoid that by:

- Checking out local branches with explicit `refs/heads/...` refs.
- Fetching only the upstream release tag needed for the sync instead of all
  upstream tags.
- Pushing with `HEAD:refs/heads/master` or `HEAD:refs/heads/mobile-cloud-sync`.
- Dispatching downstream workflows with explicit branch refs.

## Manual Sync

Use this when Actions is unavailable or a conflict needs local attention:

```bash
git fetch origin refs/heads/master:refs/remotes/origin/master
git checkout -B master refs/remotes/origin/master
git fetch upstream --no-tags --prune +refs/tags/<upstream-version>:refs/tags/<upstream-version>
git merge --no-edit refs/tags/<upstream-version>
./update.sh
flutter pub get
flutter analyze
flutter build linux --release --dart-define=MUSIFY_CLOUD_SYNC_URL=<sync-endpoint>
git push origin HEAD:refs/heads/master
```

Then create a desktop release:

```bash
gh workflow run desktop_release.yml --ref refs/heads/master -f tag=desktop-v<version> -f prerelease=false
```

If Actions is still blocked, build Linux locally and use a Windows machine for
the Windows assets, then upload the files manually:

```bash
flutter build linux --release
.github/scripts/package_linux_desktop.sh
gh release create desktop-v<version> build/desktop-artifacts/* --latest
```

## Offline Mode Notes

Offline mode is manual and local-only. It is not included in Cloud Sync, so one
device going offline does not force another synced device offline.

## Desktop Volume Control

The desktop volume slider is a downstream desktop feature. It is exposed only on
desktop targets and uses the existing `just_audio` player volume, so it does not
change upstream mobile behavior. The control appears in:

- `lib/widgets/mini_player.dart`, beside the miniplayer playback controls.
- `lib/widgets/now_playing/bottom_actions_row.dart`, in the expanded player
  action bar.

The shared widget is `lib/widgets/desktop_volume_control.dart`, and the audio
API is exposed by `MusifyAudioHandler.volumeStream`, `volume`, and `setVolume`.

## Remotes

Recommended local remotes:

```bash
git remote add origin https://github.com/elias001011/Musify-Desktop-Port.git
git remote add upstream https://github.com/gokadzev/Musify.git
```

The original upstream project should remain the source of application updates.
Desktop-only changes should stay small and easy to carry forward.
