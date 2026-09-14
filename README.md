# Musify Desktop Port

Unofficial Windows and Linux desktop port of
[Musify](https://github.com/gokadzev/Musify), created and maintained upstream by
Valeri Gokadze and contributors.

<!-- download-counts:start -->
[![Musify Desktop Port downloads](https://img.shields.io/badge/desktop%20downloads-95-2F6FE0?style=for-the-badge&logo=github)](https://github.com/elias001011/Musify-Desktop-Port/releases)
[![Musify Cloud downloads](https://img.shields.io/badge/Musify%20Cloud-7-006A71?style=for-the-badge)](https://github.com/elias001011/Musify-Desktop-Port/releases)

<sub>102 downloads across every release of both products. Updated weekly.</sub>
<!-- download-counts:end -->

This repository exists to ship **Musify for Windows and Linux**. The Android
companion **Musify Cloud** also lives here because the desktop port's optional
Local Sync needs a phone end — see [Musify Cloud](#musify-cloud) below.

None of these are official Musify releases. Nothing here tries to turn Musify
into a different app — upstream code is kept as close to original as it can be.

| | | |
|---|---|---|
| **Musify Desktop Port** | Windows, Linux | the actual port. `desktop-v*` releases, `master` branch |
| **Musify Cloud** | Android | original Musify + the other end of Local Sync. `mobile-v*`, `mobile-cloud-sync` |

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
It currently tracks the same `just_audio` version as upstream (`^0.10.6`);
when bumping it, check that the `just_audio_media_kit` bridge still resolves
against the new version, since the bridge is built against a specific
`just_audio` release and a mismatch can break playback.

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

**Desktop layout.** Settings has a **Desktop layout** section, shown only on
Windows, Linux and macOS, with two things a phone build has no need for:

- *Interface scale.* A slider (80%–160%) that scales the app's text through a
  `MediaQuery` `textScaler` override at the root, plus the sidebar and playback
  icon clusters (fixed-size widgets a text scaler alone does not touch). A
  Flutter desktop app renders its own text and only grows it when the toolkit
  picks up the environment's scaling factor; a bare tiling window manager such
  as i3 sets none, so the UI comes out small. This makes the size an in-app
  setting instead, independent of the window manager. It is stored as
  `interfaceScale` and applied on top of any system scaling.
- *Keyboard shortcuts.* A screen listing every playback and navigation action
  with its current key combination; each one can be rebound (press the new
  combination, conflicts are rejected) and the whole set can be reset to
  defaults. The shortcuts are handled app-wide but stand down whenever a text
  field is focused, so typing a space in the search box never toggles playback.

  | Action | Default |
  |---|---|
  | Play / pause | `Space` |
  | Previous / next track | `Ctrl+←` / `Ctrl+→` |
  | Seek backward / forward | `Shift+←` / `Shift+→` |
  | Volume down / up | `Ctrl+↓` / `Ctrl+↑` |
  | Toggle shuffle | `Ctrl+S` |
  | Cycle repeat mode | `Ctrl+R` |
  | Open / close the player | `Ctrl+P` |
  | Make current song available offline | `Ctrl+D` |
  | Focus the search field | `Ctrl+F` |
  | Go back | `Alt+←` |
  | Go to Home / Search / Library / Settings | `Ctrl+1` … `Ctrl+4` |

  Custom bindings live under `keyboardShortcuts` in settings storage. On Linux
  the numpad Enter key also submits a search, matching the main Enter key.
  Escape is not remappable, but it leaves the search field and dismisses the
  settings pop-ups (theme mode, accent color, ...) and the shortcut-capture
  dialog.

**Packaging.** The Linux `.deb` declares its real runtime needs
(`libgtk-3-0`, `libstdc++6`, and `libmpv2 | libmpv1 | libmpv-dev`) so libmpv
arrives with the package instead of failing at first play. Windows gets an Inno
Setup installer and a portable zip.

**Local Sync**, which is its own section below.

### What it deliberately does not change

Search, playback logic, the library, playlists, offline downloads, lyrics, the
theme and the general UI are upstream's. The port keeps startup and core changes
small on purpose: the smaller the diff, the less often an upstream release
conflicts with it, and the sync workflow can stay automatic.

## Local Sync

Optional and off by default. It exists so one person's library can follow them
between a desktop and a phone, and it is the reason Musify Cloud exists at all.

It replaces an earlier cloud-based sync that stored a backup on a server. The
current design follows [Sonora](https://github.com/gmstyle/sonora)'s
peer-to-peer sync instead: the devices talk to each other **directly over
Wi-Fi**. No account, no passphrase, no server, nothing leaves your network.

### How it works

**Devices find each other.** With Local Sync on, each device runs a small HTTP
server inside the app and answers a UDP broadcast on the local network. The
Devices screen scans and lists what it finds.

**Pair once with a PIN.** The first time two devices meet, the device being
paired to shows a 4-digit PIN and the other one asks for it. After that they
remember each other and sync without asking again. Long-press a device to
forget it.

**Both sides merge.** A sync sends this device's library to the other one,
which merges it and answers with its own merged library, which is then merged
back here. One round trip and both devices have the same liked songs, playlists
(custom ones included, folders too), pinned playlists, recently played, liked
radio stations and search history.

**The merge only adds.** Nothing is ever removed by a sync, so it is safe to
run in any direction at any time. The flip side is that deletions do not
propagate: remove a song on one device and the next sync brings it back from
the other, unless you remove it there too. Two custom playlists created
separately with the same name follow the **Same-name playlists** setting: merge
their songs (default), keep both, or let the other device win.

**When it syncs.** With **Automatic sync** on, a device syncs with every paired
device it can see at startup, about 30 seconds after you change something, and
every 30 minutes. You can also sync by hand from the Devices screen.

**What stays local.** Settings (theme, quality, keyboard shortcuts, interface
scale), offline downloads, the listening recap and offline mode are not
synced; a phone and a desktop are meant to differ there.

### Limits worth knowing

- Both devices must be on the same regular Wi-Fi, with Local Sync on. Guest
  networks and "AP isolation" block device-to-device traffic.
- Additive merge, as above: no deletions, no history, no rollback.
- After pairing, a device id is what identifies a trusted device on the
  network. Fine for a home network; forget devices you no longer use.
- Windows asks once whether Musify may accept private-network connections;
  Linux firewalls may need UDP `53531` open.

Full details, the merge rules and the wire protocol are in
[docs/local-sync.md](docs/local-sync.md).

---

# Musify Cloud

The Android companion to the desktop port. Original mobile Musify with the same
optional Local Sync described above, and nothing else. It exists because sync
needs two ends: this is the phone the desktop port can find on the Wi-Fi and
merge libraries with. The name is historical, from when the sync went through
a cloud backend; it now works entirely on the local network.

It uses its own application id (`com.elias001011.musifycloud`), name and icon, so
it installs beside original Musify rather than replacing it. Downloads are
`MusifyCloud.apk` on `mobile-v*` releases.

## How to get both

| Want | Get |
|---|---|
| Desktop app for Windows/Linux | [desktop-v* releases](https://github.com/elias001011/Musify-Desktop-Port/releases) — `Musify-linux-x64.deb`, `Musify-linux-x64.tar.gz`, `Musify-windows-x64-setup.exe`, `Musify-windows-x64-portable.zip` |
| Phone app that syncs with it | [mobile-v* releases](https://github.com/elias001011/Musify-Desktop-Port/releases) — `MusifyCloud.apk` |

Install the desktop build, install Musify Cloud on your phone, turn on Local
sync on both while they are on the same Wi-Fi, pair them once with the PIN, and
your playlists, liked songs and history follow you between the two.

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