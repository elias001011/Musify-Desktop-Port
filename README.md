# Musify Desktop Port

Unofficial Windows and Linux desktop port of
[Musify](https://github.com/gokadzev/Musify), created and maintained upstream by
Valeri Gokadze and contributors.

<!-- download-counts:start -->
[![Musify Desktop Port downloads](https://img.shields.io/badge/desktop%20downloads-80-2F6FE0?style=for-the-badge&logo=github)](https://github.com/elias001011/Musify-Desktop-Port/releases)
[![Musify Cloud downloads](https://img.shields.io/badge/Musify%20Cloud-7-006A71?style=for-the-badge)](https://github.com/elias001011/Musify-Desktop-Port/releases)

<sub>87 downloads across every release of both products. Updated daily.</sub>
<!-- download-counts:end -->

This repository exists to ship **Musify for Windows and Linux**. The Android
companion **Musify Cloud** also lives here because the desktop port's optional
cloud sync needs a phone end — see [Musify Cloud](#musify-cloud) below.

None of these are official Musify releases. Nothing here tries to turn Musify
into a different app — upstream code is kept as close to original as it can be.

| | | |
|---|---|---|
| **Musify Desktop Port** | Windows, Linux | the actual port. `desktop-v*` releases, `master` branch |
| **Musify Cloud** | Android | original Musify + the other end of cloud sync. `mobile-v*`, `mobile-cloud-sync` |

---

# The desktop port

## Downloads

Every `desktop-v*` release ships:

- `Musify-linux-x64.deb` for Debian/Ubuntu based distributions.
- `Musify-linux-x64.tar.gz` for portable Linux use.
- `Musify-windows-x64-setup.exe` for Windows installation.
- `Musify-windows-x64-portable.zip` for portable Windows use.
- `SHA256SUMS.txt` for artifact verification.

[Download the latest desktop release](https://github.com/elias001011/Musify-Desktop-Port/releases/latest)
and pick the files for your platform.

The in-app updater follows this channel, which is why `desktop-v*` releases are
the ones allowed to be GitHub **Latest**.

## What changes from original Musify

Upstream Musify is an Android app. Everything below exists because of that — it
is porting work and desktop plumbing, not a redesign. Two kinds of change: what
is *required* to make Musify run on a PC at all, and what is *added* on top as
an optional desktop convenience.

### Required: making it run on a PC

**The desktop runners.** Flutter needs a native host per platform, and upstream
has only the Android one. This repository adds the `linux/` and `windows/`
trees: CMake builds, a GTK application for Linux, a Win32 window for Windows,
the generated plugin registrants, and a Windows app icon and manifest. That is
around 2,800 lines of platform scaffolding that upstream has no reason to carry.

**Audio playback.** `just_audio`, which Musify uses for everything, has no
native desktop implementation. Playback goes through
[`just_audio_media_kit`](https://pub.dev/packages/just_audio_media_kit) instead,
backed by libmpv via `media_kit_libs_linux` and `media_kit_libs_windows_audio`,
initialised with a single `JustAudioMediaKit.ensureInitialized()` at startup.
This also pins `just_audio` to exactly `0.10.5` rather than tracking upstream's
`^0.10.6`, because the media_kit bridge is built against that version — the pin
is deliberate and is the reason a version bump can need attention on sync.

**Android-only APIs that used to run unconditionally.** Two of them would crash
or hang a desktop build at startup:

- *The equalizer.* Upstream constructs an `AndroidEqualizer()` and installs it in
  the audio pipeline with no platform check. Here it is created only on Android,
  the field is nullable, and every call site handles its absence, so the
  equalizer screen simply reports itself unavailable off Android.
- *Share intents.* Upstream subscribes to `ReceiveSharingIntent.getTextStream()`
  during init, which only exists on Android and iOS. The subscription is now
  optional and only made on those platforms.

**The updater.** Upstream checks a JSON file on its own `update` branch and
points users at Android releases. The desktop updater reads this repository's
release list, keeps only `desktop-v*` tags, detects the CPU architecture with
`uname -m`, and picks the matching asset — falling back to the release page if
it cannot match one.

### Added: optional desktop conveniences

**Volume control.** A phone has hardware volume buttons; a desktop app is
expected to have its own. The miniplayer and the expanded player show a speaker
button that expands into an inline slider, wired to the audio handler's volume
stream. It renders only on Windows, Linux and macOS.

**Packaging.** The Linux `.deb` declares its real runtime needs
(`libgtk-3-0`, `libstdc++6`, and `libmpv2 | libmpv1 | libmpv-dev`) so libmpv
arrives with the package instead of failing at first play. Windows gets an Inno
Setup installer and a portable zip.

**Cloud Sync**, which is its own section below.

### What it deliberately does not change

Search, playback logic, the library, playlists, offline downloads, lyrics, the
theme and the general UI are upstream's. The port keeps startup and core changes
small on purpose: the smaller the diff, the less often an upstream release
conflicts with it, and the sync workflow can stay automatic.

## Cloud Sync

Optional and off by default. It exists so one person's library can follow them
between a desktop and a phone, and it is the reason Musify Cloud exists at all.

### How it works

**A passphrase, not an account.** You type the same passphrase on both devices.
The app never sends it: it is hashed with SHA-256 into an account id, and only
that hash reaches the server. There is no sign-up, no email, no password reset —
lose the passphrase and the backup is unreachable.

**One record per passphrase.** The account id is the storage key: the backend
keeps a single JSON document per id, and both devices read and write that one
document.

**What a snapshot contains.** A full dump of the app's two Hive boxes,
`settings` and `user` — so preferences, playlists, liked songs, liked artists,
recently played, and most-played data. A few keys are excluded and stay on the
device: internal sync bookkeeping and offline mode.

**Transport.** JSON, gzipped and base64-wrapped when it is large enough to be
worth it. A library big enough to exceed the backend's size limit gets a clear
error rather than a silent truncation.

**When it uploads.** With automatic uploads on, the manager watches both Hive
boxes and uploads about 20 seconds after the last change, so editing a playlist
produces one upload rather than one per song. You can also sync manually from
Settings.

**How a conflict resolves.** It does not merge. Each snapshot carries a
timestamp, and the newer one wins, whole. Change a playlist on your phone and a
different playlist on your desktop without syncing in between, and the second
upload replaces the first — one of the two sets of changes is gone. That is a
real limitation, not a bug to be worked around: this is a personal
one-user-two-devices feature, not a multi-device database.

**After a restore.** Replacing local data would otherwise leave the running app
showing stale lists, so a restore refreshes settings, songs and playlists from
storage and bumps a signal the UI listens to.

### Limits worth knowing

- Not end-to-end encrypted. The backend stores readable JSON, so treat it as
  private-but-not-secret. See [docs/cloud-sync.md](docs/cloud-sync.md).
- Last-writer-wins at the whole-backup level, as above.
- One backup per passphrase: no history, no rollback.

### Running your own backend

Cloud sync needs a backend URL compiled in:

```bash
flutter build linux --release --dart-define=MUSIFY_CLOUD_SYNC_URL=https://example.com
```

For GitHub Actions releases, set the repository variable
`MUSIFY_CLOUD_SYNC_URL`. With no value the app still builds, and the sync screen
explains that no backend is configured. The reference backend is a Cloudflare
Worker over KV; setup is in [docs/cloud-sync.md](docs/cloud-sync.md).

---

# Musify Cloud

The Android companion to the desktop port. Original mobile Musify with the same
optional Cloud Sync described above, and nothing else. It exists because sync
needs two ends: the desktop port talks to a server, and this is the phone that
can share the same backup with it.

It uses its own application id (`com.elias001011.musifycloud`), name and icon, so
it installs beside original Musify rather than replacing it. Downloads are
`MusifyCloud.apk` on `mobile-v*` releases.

## How to get both

| Want | Get |
|---|---|
| Desktop app for Windows/Linux | [desktop-v* releases](https://github.com/elias001011/Musify-Desktop-Port/releases) — `Musify-linux-x64.deb`, `Musify-linux-x64.tar.gz`, `Musify-windows-x64-setup.exe`, `Musify-windows-x64-portable.zip` |
| Phone app that syncs with it | [mobile-v* releases](https://github.com/elias001011/Musify-Desktop-Port/releases) — `MusifyCloud.apk` |

Install the desktop build, install Musify Cloud on your phone, type the same
passphrase into Cloud Sync on both, and your playlists and settings follow you
between the two.

---

# Releases and maintenance

## Release channels

Two families in one release list:

- `desktop-v*` — Windows/Linux. Allowed to be GitHub **Latest**, because the
  desktop updater follows the repository's latest release.
- `mobile-v*` — Musify Cloud Android.

The Android channel is deliberately **never** marked Latest, and the release
workflow re-pins the newest `desktop-v*` release afterwards. Without that, GitHub
promotes whichever release was published most recently and the desktop updater
starts offering desktop users an APK. Each app also filters releases by tag
prefix, so it only ever sees its own channel.

## How the two stay in sync

```
gokadzev/Musify publishes a release
        |
        +---> Sync Desktop Upstream Release ---> master ------------> desktop-v*
        |
        +---> Sync Mobile Upstream Release ----> mobile-cloud-sync --> mobile-v*
```

Every sync merges plainly and **stops on conflict**. Earlier versions retried
with `-X ours`/`-X theirs`, which reported success while keeping fork code that
called a refactored upstream API — that is how a release once shipped that could
not build. Nothing is pushed unless `flutter analyze` is clean, and the release
build is dispatched against that exact validated commit. When a merge does
conflict the run lists the files and fails, because Actions cannot guess the
right answer.

See [docs/maintenance.md](docs/maintenance.md) for the full release flow.

## Downstream adjustments

Maintenance details rather than features:

- GitHub Actions workflows for desktop packaging, Musify Cloud packaging, and
  the upstream syncs.
- Workflow refs are written as `refs/heads/...` where possible, and upstream sync
  fetches only the selected release tag. Upstream has a historical tag named
  `master`, and fetching it makes the local branch name ambiguous inside a job.

---

## Credits

All core Musify application work belongs to the upstream project:

- Upstream repository: https://github.com/gokadzev/Musify
- Original author/maintainer: Valeri Gokadze
- Upstream contributors: https://github.com/gokadzev/Musify/graphs/contributors

This desktop port is an unofficial downstream packaging and compatibility effort.
It is not a replacement for the upstream project and is not presented as an
official Musify release channel.

## License

Musify is free software licensed under GPL v3.0. This desktop port keeps the same
license and copyright notices as the upstream project.

See [LICENSE](LICENSE) for the full license text.