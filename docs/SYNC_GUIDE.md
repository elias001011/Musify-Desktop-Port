# Musify Desktop Port - Synchronization & Release Guide

Internal documentation for synchronizing `gokadzev/Musify` upstream with our maintained branches:
- **mobile-cloud-sync**: Musify Cloud (Android with Cloud Sync)
- **master**: Musify Desktop Port (Windows/Linux)

## Current Status (2026-07-26)

| Branch | Version | Remote | Sync Status |
|--------|---------|--------|-------------|
| mobile-cloud-sync | 10.1.1 | origin | ✅ Synced |
| master | 10.1.1 | origin | ✅ Synced |
| upstream (gokadzev/Musify) | 10.1.1 | reference | 📍 Current |

## Automated Synchronization

### Mobile: `sync_mobile_upstream_release.yml`
- **Schedule**: Weekly, Sunday 03:17 UTC (cron: `17 3 * * 0`)
- **Branch**: mobile-cloud-sync
- **Process**:
  1. Resolve the latest upstream release tag
  2. Check if the matching mobile-v* release already exists
  3. If not, `git merge --no-edit` the upstream tag — **conflicts abort the run**
  4. Refresh `lib/constants/version.dart` (`update.sh`) and `pubspec.lock`
  5. `flutter analyze` — the run stops here if the merged tree does not compile
  6. Push to origin/mobile-cloud-sync
  7. Dispatch mobile_release.yml against the exact validated commit
  8. On failure: write the reason to the run summary, and try to open an issue

### Desktop: `sync_desktop_upstream_release.yml`
- **Schedule**: Weekly, Sunday 03:17 UTC (cron: `17 3 * * 0`)
- **Branch**: master
- **Process**: Same as mobile sync but for desktop
  - Also dispatches desktop_release.yml on success

### Why conflicts abort instead of auto-resolving

Both workflows used to retry a failed merge with `-X ours` and then `-X theirs`.
That made the sync step report success while producing a tree that either called
a refactored upstream API or silently lost an upstream fix — exactly what broke
the 10.1.1 desktop release build. Automatic resolution is gone; a conflict is a
human's job. The `flutter analyze` gate is the backstop: nothing reaches a branch
or a release build unless it analyzes clean.

## Expected Merge Conflicts & Resolution

When syncing with upstream, these files will conflict predictably:

### 1. `lib/screens/settings_page.dart` (Data Restoration)
**Conflict Pattern**: Two different data restoration approaches

**LOCAL (mobile-cloud-sync)** - Cloud Sync preparation:
```dart
if (result.success) {
  refreshBackedUpStateFromStorage();
  await CloudSyncManager.instance.rebindStorageListeners();
  CloudSyncManager.instance.markBackedUpStateChanged();
```

**UPSTREAM (gokadzev/Musify)** - General state restoration:
```dart
if (result.success) {
  reloadSongLibraryStateFromStorage();
  reloadPlaylistLibraryStateFromStorage();
  reloadSearchHistoryFromStorage();
  wrappedEnabled.value = await getData(localStorageKeys.wrappedEnabled) as bool;
  listeningStatsService.reload();
```

**✅ Resolution**: **PRESERVE BOTH** in sequence
- Execute LOCAL code first (Cloud sync preparation)
- Then execute UPSTREAM code (state reloading)
- This ensures Cloud listeners are ready before state changes

**Final code after resolution**:
```dart
if (result.success) {
  // LOCAL: Cloud sync preparation
  refreshBackedUpStateFromStorage();
  await CloudSyncManager.instance.rebindStorageListeners();
  CloudSyncManager.instance.markBackedUpStateChanged();
  
  // UPSTREAM: State restoration
  reloadSongLibraryStateFromStorage();
  reloadPlaylistLibraryStateFromStorage();
  reloadSearchHistoryFromStorage();
  wrappedEnabled.value = await getData(localStorageKeys.wrappedEnabled) as bool;
  listeningStatsService.reload();
}
```

### 2. `lib/services/common_services.dart` (User Songs Reload)
**Conflict Pattern**: Two complementary reload strategies

**LOCAL function** - With version tracking:
```dart
void refreshUserSongsFromStorage() {
  userLikedSongsList.value = userBox.get('likedSongs', defaultValue: []);
  userRecentlyPlayed.value = userBox.get('recentlyPlayedSongs', defaultValue: []);
  userOfflineSongs.value = Hive.box('userNoBackup').get('offlineSongs', defaultValue: []);
  currentLikedSongsLength.value = userLikedSongsList.value.length;
  currentRecentlyPlayedLength.value = userRecentlyPlayed.value.length;
  currentOfflineSongsLength.value = userOfflineSongs.value.length;
  recentlyPlayedVersion.value++;  // Tracks version for Cloud sync
}
```

**UPSTREAM function** - With defensive copying:
```dart
void reloadSongLibraryStateFromStorage() {
  userLikedSongsList.value = List.from(userBox.get('likedSongs', defaultValue: []));
  userRecentlyPlayed.value = List.from(userBox.get('recentlyPlayedSongs', defaultValue: []));
}
```

**✅ Resolution**: **PRESERVE BOTH** functions
- LOCAL version: For Cloud Sync (needs version tracking)
- UPSTREAM version: For general library state reload with immutability
- Both serve different purposes; having both provides flexible reload options

### 3. `pubspec.yaml` and `pubspec.lock`
**Conflict Pattern**: Version divergence, new dependencies from upstream

**✅ Resolution**: Accept `-X theirs` (upstream version)
- Upstream always has latest tested dependency versions
- Local adjustments (if needed) are minimal
- Then run `flutter pub get` and commit the refreshed `pubspec.lock`: upstream can
  add a dependency (10.1.1 added `share_plus`) without the lockfile conflicting

### 4. `lib/main.dart` — `handleIncomingLink` (mobile only)
**Conflict Pattern**: Upstream refactors the deep link handler; we only differ in
the URI scheme.

**✅ Resolution**: Take the upstream body, keep the `musifycloud` scheme. It has to
match `android/app/src/main/AndroidManifest.xml` and the share URL built in
`lib/screens/playlist_page.dart`.

### 5. `lib/screens/library_page.dart` — library shortcuts (mobile only)
**Conflict Pattern**: Upstream appends new shortcut bars (10.1.1 added Radio
Stations); we renamed the visibility flags (`shouldShowLibraryShortcuts`,
`hasAnythingAfterOffline`).

**✅ Resolution**: Keep our flags, take the new upstream bars, and move
`borderRadius: hasAnythingAfterOffline ? BorderRadius.zero : commonCustomBarRadiusLast`
onto whatever is now the last bar.

### 6. `lib/widgets/now_playing/bottom_actions_row.dart` (desktop only)
**Conflict Pattern**: Our only change is prepending `DesktopVolumeControl` to the
actions list, but upstream keeps refactoring the widget around it. In 10.1.1 it
moved `audioId` from a constructor argument to a state field, so a `-X ours`
resolution kept `widget.audioId` and broke the build.

**✅ Resolution**: Take the upstream block verbatim and re-add only
`const DesktopVolumeControl(iconSize: 22),` as the first entry.

## Manual Synchronization Procedure

Use this when:
1. Automated workflow fails
2. You need to sync manually for testing
3. Manual conflict resolution is preferred

### Prerequisites
```bash
cd /path/to/Musify-Desktop-Port
git remote add upstream https://github.com/gokadzev/Musify.git
git fetch upstream --no-tags --prune "refs/tags/*:refs/tags/upstream-*"
```

Doing this in a `git worktree` keeps your current branch untouched:
`git worktree add ../wt-mobile mobile-cloud-sync`.

### For mobile-cloud-sync (with Musify Cloud features)
```bash
UPSTREAM=10.1.1   # upstream release tag

git checkout mobile-cloud-sync
git fetch origin
git fetch upstream --no-tags --prune "refs/tags/${UPSTREAM}:refs/tags/${UPSTREAM}"

if git merge --no-edit "refs/tags/${UPSTREAM}"; then
  echo "✅ Merge succeeded without conflicts"
else
  echo "⚠️  Conflicts detected - resolve them by hand:"
  git diff --name-only --diff-filter=U
  # See "Expected Merge Conflicts & Resolution" above, then:
  #   git add <each resolved file> && git commit
fi

# Never push before this passes: it is what CI checks, and what the release
# build would otherwise fail on after the branch has already moved.
flutter pub get
flutter analyze
git add pubspec.lock && git commit -m "chore: refresh pubspec.lock for ${UPSTREAM}" || true

git push origin mobile-cloud-sync

# Trigger mobile release build for the commit you just validated
gh workflow run mobile_release.yml --ref refs/heads/mobile-cloud-sync \
  -f version="${UPSTREAM}" \
  -f source_ref="$(git rev-parse HEAD)" \
  -f repair_existing_release=false
```

### For master (Desktop Port only)
```bash
UPSTREAM=10.1.1

git checkout master
git fetch origin
git fetch upstream --no-tags --prune "refs/tags/${UPSTREAM}:refs/tags/${UPSTREAM}"

git merge --no-edit "refs/tags/${UPSTREAM}"
# Resolve conflicts, then commit. Desktop-only trap: bottom_actions_row.dart,
# see section 6 above.

flutter pub get
flutter analyze
# Optional but cheap insurance before spending a CI cycle:
flutter build linux --release

git push origin master

# Note: desktop_release.yml takes `tag`, not `version`.
gh workflow run desktop_release.yml --ref refs/heads/master \
  -f tag="desktop-v${UPSTREAM}" \
  -f source_ref="$(git rev-parse HEAD)" \
  -f repair_existing_release=false
```

## Release Workflows

### Mobile Release: `mobile_release.yml`
**Inputs**:
- version: "10.1.0" (upstream Musify version)
- source_ref: "refs/heads/mobile-cloud-sync" (branch to build)
- repair_existing_release: false (create new or fail if exists)

**Outputs**:
- mobile-v10.1.0 GitHub release (with APKs)
- MusifyCloud-arm64-v8a.apk (optimized for ARM64)
- MusifyCloud.apk (universal)
- SHA256SUMS.txt (verification)

**Release Settings**:
- NOT marked as "Latest" (desktop releases reserved for Latest)
- Includes Musify Cloud-specific release notes
- Contains link to cloud-sync.md documentation

**Trigger**:
```bash
gh workflow run mobile_release.yml --ref refs/heads/mobile-cloud-sync \
  -f version="10.1.0" \
  -f source_ref="refs/heads/mobile-cloud-sync"
```

### Desktop Release: `desktop_release.yml`
**Inputs** (note: `tag`, not `version`):
- tag: "desktop-v10.1.1" — must match `pubspec.yaml`, optionally with a
  `-<revision>` suffix (`desktop-v10.1.1-2`); the preflight job rejects anything else
- source_ref: commit/branch to build (defaults to the workflow ref)
- repair_existing_release: false (create new, or fail if the release exists)
- prerelease: false

**Outputs**:
- desktop-v10.1.1 GitHub release
- Musify-linux-x64.deb (Debian/Ubuntu package)
- Musify-linux-x64.tar.gz (Linux portable)
- Musify-windows-x64-setup.exe (Inno Setup installer)
- Musify-windows-x64-portable.zip (Windows portable)
- SHA256SUMS.txt (verification)

**Release Settings**:
- **Marked as "Latest"** (for automatic updater)
- Includes desktop-specific build notes
- References upstream Musify repository

**Build Environment**:
- Linux: Ubuntu latest (clang, GTK3, pkg-config, ninja-build, dpkg-dev)
- Windows: Windows latest (MSVC + Inno Setup via choco)

**Trigger**:
```bash
gh workflow run desktop_release.yml --ref refs/heads/master \
  -f tag="desktop-v10.1.1" \
  -f source_ref="$(git rev-parse HEAD)"
```

## Git Reference Commands

```bash
# List all tags sorted by version
git tag -l --sort=-version:refname | head -20

# Fetch specific upstream tag
git fetch upstream --no-tags --prune "refs/tags/10.1.0:refs/tags/10.1.0"

# View merge conflicts
git status                           # Shows all conflicts
git diff --name-only --diff-filter=U  # Only conflicted files

# Inspect one side of a conflicted file before resolving
git show :2:lib/main.dart   # ours
git show :3:lib/main.dart   # theirs (upstream)

# Per-file strategies. Only for files you have actually reviewed - blanket
# -X ours / -X theirs on a whole merge is how 10.1.1 shipped broken.
git checkout --ours <file>    # keep our side of that file
git checkout --theirs <file>  # take upstream's side of that file

# Abort failed merge
git merge --abort

# View what changed between branches
git log --oneline master...upstream/master
git log --oneline mobile-cloud-sync...upstream/master

# Check if tag exists
git rev-list "desktop-v10.1.0" >/dev/null 2>&1 && echo "exists" || echo "not found"
```

## Troubleshooting

### Sync Workflow Fails
**Symptoms**: GitHub Actions shows red X on sync job

**Steps**:
1. Check Actions logs at: https://github.com/elias001011/Musify-Desktop-Port/actions
2. Look for merge error or failed validation
3. Run manual merge locally to test
4. If manual merge works, file issue with logs

### Unexpected Conflicts in Other Files
**Symptoms**: Merge fails on file not listed in "Expected Conflicts"

**Steps**:
1. Inspect conflict: `git show :1:path/to/file` (base), `:2:` (ours), `:3:` (theirs)
2. Resolve manually or use: `git checkout --ours path/to/file` or `--theirs`
3. Add resolved file: `git add path/to/file`
4. Document new conflict pattern in this guide

### Release Build Fails
**Symptoms**: mobile_release.yml or desktop_release.yml shows error

**Possible Causes**:
- Missing signing secrets (mobile)
- Flutter version mismatch in pubspec.yaml
- Insufficient disk space (Linux/Windows builds are large)
- Missing dependencies (check workflow logs)

**Solution**:
1. Check specific error in workflow logs
2. Verify secrets: `gh secret list`
3. Verify Flutter version: `grep flutter pubspec.yaml`

### Worktree State Issues
**Mobile worktree**: `/home/elias/Downloads/Musify-Desktop-Port`
**Desktop worktree**: `/home/elias/Downloads/Musify-Desktop-Port-master`

**If out of sync**:
```bash
cd /path/to/worktree
git fetch origin
git status
```

## Key Files

| File | Purpose |
|------|---------|
| `.github/workflows/sync_mobile_upstream_release.yml` | Auto-sync mobile branch, handle conflicts, trigger release |
| `.github/workflows/sync_desktop_upstream_release.yml` | Auto-sync desktop branch, handle conflicts, trigger release |
| `.github/workflows/mobile_release.yml` | Build & publish mobile APKs |
| `.github/workflows/desktop_release.yml` | Build & publish desktop (Linux/Windows) |
| `docs/SYNC_GUIDE.md` | This document |

## Contact & Updates

For sync issues or documentation updates:
1. Review workflow files in `.github/workflows/`
2. Check git history: `git log --oneline -- docs/SYNC_GUIDE.md`
3. See repository CONTRIBUTING.md for guidelines
