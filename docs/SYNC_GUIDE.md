# Musify Desktop Port - Synchronization & Release Guide

Internal documentation for synchronizing `gokadzev/Musify` upstream with our maintained branches:
- **mobile-cloud-sync**: Musify Cloud (Android with Cloud Sync)
- **master**: Musify Desktop Port (Windows/Linux)

## Current Status (2026-06-30)

| Branch | Version | Remote | Sync Status |
|--------|---------|--------|-------------|
| mobile-cloud-sync | 10.1.0 | origin | ✅ Synced |
| master | 10.1.0 | origin | ✅ Synced |
| upstream (gokadzev/Musify) | 10.1.0 | reference | 📍 Current |

## Automated Synchronization

### Mobile: `sync_mobile_upstream_release.yml`
- **Schedule**: Every 6 hours (cron: `17 */6 * * *`)
- **Branch**: mobile-cloud-sync
- **Process**:
  1. Fetch latest upstream release tag
  2. Check if mobile-v* release already exists
  3. If not, attempt merge with fallback strategies:
     - `git merge --no-edit` (clean merge)
     - `-X ours` (preserve Musify Cloud changes) ← Most common
     - `-X theirs` (accept upstream changes)
  4. Validate pubspec.yaml
  5. Push to origin/mobile-cloud-sync
  6. Automatically dispatch mobile_release.yml
  7. Create issue if failed

### Desktop: `sync_desktop_upstream_release.yml`
- **Schedule**: Every 6 hours (cron: `17 */6 * * *`)
- **Branch**: master
- **Process**: Same as mobile sync but for desktop
  - Also dispatches desktop_release.yml on success

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

### For mobile-cloud-sync (with Musify Cloud features)
```bash
git checkout mobile-cloud-sync
git fetch origin

# Fetch upstream tag
git fetch upstream --no-tags --prune "refs/tags/10.1.0:refs/tags/10.1.0"

# Attempt merge
if git merge --no-edit refs/tags/10.1.0; then
  echo "✅ Merge succeeded without conflicts"
else
  echo "⚠️  Conflicts detected - resolving..."
  
  # Resolve conflicts as documented above
  # Edit: lib/screens/settings_page.dart (preserve both blocks)
  # Edit: lib/services/common_services.dart (keep both functions)
  # For: pubspec.yaml and pubspec.lock (accept upstream)
  
  git add lib/screens/settings_page.dart lib/services/common_services.dart
  git add pubspec.yaml pubspec.lock
fi

git commit -m 'Merge upstream 10.1.0 into mobile-cloud-sync; preserve Musify Cloud functionality'
git push origin mobile-cloud-sync

# Trigger mobile release build
gh workflow run mobile_release.yml --ref refs/heads/mobile-cloud-sync \
  -f version="10.1.0" \
  -f source_ref="refs/heads/mobile-cloud-sync" \
  -f repair_existing_release=false
```

### For master (Desktop Port only)
```bash
git checkout master
git fetch origin

# Same fetch & merge procedure
git fetch upstream --no-tags --prune "refs/tags/10.1.0:refs/tags/10.1.0"

# Merge (conflicts will be similar - resolve with same strategy)
git merge --no-edit refs/tags/10.1.0

# Resolve conflicts (same files, similar patterns)
git add -A
git commit -m 'Merge upstream 10.1.0 into master; preserve desktop functionality'
git push origin master

# Trigger desktop release build
gh workflow run desktop_release.yml --ref refs/heads/master \
  -f version="10.1.0" \
  -f source_ref="refs/heads/master" \
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
**Inputs**: Same as mobile_release.yml

**Outputs**:
- desktop-v10.1.0 GitHub release
- Musify-Linux-x64.tar.gz (Linux portable)
- Musify-Windows-x64.tar.gz (Windows portable)
- SHA256SUMS.txt (verification)

**Release Settings**:
- **Marked as "Latest"** (for automatic updater)
- Includes desktop-specific build notes
- References upstream Musify repository

**Build Environment**:
- Linux: Ubuntu latest (GTK3, pkg-config, ninja-build)
- Windows: Windows latest (MSVC)

**Trigger**:
```bash
gh workflow run desktop_release.yml --ref refs/heads/master \
  -f version="10.1.0" \
  -f source_ref="refs/heads/master"
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

# Merge with strategies
git merge -X ours refs/tags/10.1.0    # Keep local on conflicts
git merge -X theirs refs/tags/10.1.0  # Accept upstream on conflicts
git merge -X recursive refs/tags/10.1.0  # More aggressive auto-resolution

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
