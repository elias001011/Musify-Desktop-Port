# Musify Cloud Maintenance

This branch tracks upstream mobile Musify and adds the Musify Cloud layer on
top. The goal is to keep upstream changes flowing while preserving our Android
package identity, update channel and Cloud Sync code.

## Branch Roles

- `mobile-cloud-sync` is the Android Musify Cloud branch.
- `master` is the desktop port branch.
- Upstream source is `gokadzev/Musify`.

## Automatic Mobile Flow

The `Sync Mobile Upstream Release` workflow runs on a schedule and can also be
started manually.

Expected flow:

1. Resolve the latest upstream release tag from `gokadzev/Musify`.
2. Map that upstream version to `mobile-v<version>`.
3. Stop if a complete `mobile-v<version>` release already exists.
4. Merge the upstream tag into `mobile-cloud-sync`.
5. Run `flutter pub get` and `flutter analyze`.
6. Push the updated branch.
7. Dispatch `Build Musify Cloud Android Release`.
8. Publish APK assets to `mobile-v<version>`.
9. Mark the mobile release as not latest.

Mobile releases must not be marked as GitHub Latest. The desktop updater follows
the repository's Latest release, so Latest belongs to `desktop-v*` releases.

## Manual Mobile Release

Use this only when rebuilding a known-good branch or repairing a broken release.

```bash
gh workflow run mobile_release.yml \
  --ref mobile-cloud-sync \
  -f version="10.0.8" \
  -f source_ref="mobile-cloud-sync" \
  -f repair_existing_release=false
```

Set `repair_existing_release=true` only when intentionally replacing assets on
an existing `mobile-v*` release.

## Merge Conflicts

If upstream changes a file that Musify Cloud also changed, `git merge` can fail
inside GitHub Actions. The workflow should then open an issue with a link to the
failed run.

Manual recovery:

1. Fetch the latest refs locally.
2. Checkout `mobile-cloud-sync`.
3. Merge the upstream tag that failed.
4. Resolve conflicts while preserving Musify Cloud changes.
5. Run `flutter pub get`.
6. Run `flutter analyze`.
7. Push `mobile-cloud-sync`.
8. Run the mobile release workflow manually if needed.

## Cloud Sync Notes

Cloud Sync currently stores one latest full backup per passphrase. The newest
backup wins. This is simple and works well for a small personal sync feature,
but it is not a multi-user database and it does not do field-level conflict
merges.

See `docs/cloud-sync.md` for backend setup, limits and security notes.
