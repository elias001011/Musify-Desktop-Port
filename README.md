# Musify Desktop Port

Unofficial Windows and Linux desktop port of
[Musify](https://github.com/gokadzev/Musify), created and maintained upstream by
Valeri Gokadze and contributors.

<!-- download-counts:start -->
[![Musify Desktop Port downloads](https://img.shields.io/badge/desktop%20downloads-174-2F6FE0?style=for-the-badge&logo=github)](https://github.com/elias001011/Musify-Desktop-Port/releases)
[![Musify Cloud downloads](https://img.shields.io/badge/Musify%20Cloud-9-006A71?style=for-the-badge)](https://github.com/elias001011/Musify-Desktop-Port/releases)

<sub>183 downloads across every release of both products. Updated weekly.</sub>
<!-- download-counts:end -->

This repository exists to ship **Musify for Windows and Linux**. The Android
companion builds from the same `master` branch, with optional Local Sync.
Desktop-only settings and controls stay off Android.

None of these are official Musify releases. Nothing here tries to turn Musify
into a different app — upstream code is kept as close to original as it can be.

| | | |
|---|---|---|
| **Musify Desktop Port** | Windows, Linux | the actual port. `desktop-v*` releases, `master` branch |
| **Musify Android** | Android | upstream mobile UI + Local Sync. `mobile-v*`, `master` |

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

Upstream now includes initial desktop support. This repository maintains its
desktop integrations, packaging and optional features while keeping the mobile
interface close to upstream.

### Required: making it run on a PC

**The desktop runners.** Flutter needs a native host per platform. Upstream now
includes a basic Linux runner. This repository keeps its customized GTK runner
and adds the Windows host, with desktop window controls, platform packaging and
app icons. Upstream Linux changes are reconciled with these integrations when
syncing, so the desktop features remain available on both platforms.

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
- *Title bar in app colours.* On by default: the window's title bar takes the
  app's colours and follows its light/dark mode. Turn it off to use the
  system's colours instead. The title bar keeps the same compact height either
  way. It is stored as `customTitleBar`.
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

Optional and off by default. Pair Android, Linux and Windows devices on the
same local network by typing the six-digit PIN shown on the other device. Choose which
categories to share: favourites, playlists/folders/pins, recently played,
listening recap, searches and radio favourites. Settings and downloads stay local.

Sync propagates additions, edits and deletions. Playlists match by ID; separate
same-name playlists remain separate. Recap copies whole months, including history;
when a month conflicts, higher listening time wins without summing the devices.
Multiple paired devices are supported. Unreachable devices retain data and trust
and can catch up after reconnecting. Messages are authenticated and encrypted.

Both ends need the current PIN pairing; pairings already established keep
working. Apps must be running and reachable on the LAN. Physical-device testing
remains important for firewalls, Wi-Fi discovery and Android background limits.

See [docs/local-sync.md](docs/local-sync.md) for rules, failure handling and tests.

---

# Musify Android

The Android companion uses upstream mobile UI plus optional Local Sync. Both
platform families build from `master`; Android does not expose desktop settings.
Its application ID remains `com.elias001011.musifycloud` so existing companion
installations retain their data and can update normally. It installs beside
original Musify. The historical APK filename remains `MusifyCloud.apk`.

## How to get both

| Want | Get |
|---|---|
| Desktop app for Windows/Linux | [desktop-v* releases](https://github.com/elias001011/Musify-Desktop-Port/releases) — `Musify-linux-x64.deb`, `Musify-linux-x64.tar.gz`, `Musify-windows-x64-setup.exe`, `Musify-windows-x64-portable.zip` |
| Phone app that syncs with it | [mobile-v* releases](https://github.com/elias001011/Musify-Desktop-Port/releases) — `MusifyCloud.apk` |

Install the desktop build, install the Android companion on your phone, turn on Local
sync on both while they are on the same Wi-Fi, pair them once with the PIN, and
your playlists, liked songs and history follow you between the two.

---

# Releases and maintenance

## Release channels

Two families in one release list:

- `desktop-v*` — Windows/Linux. Allowed to be GitHub **Latest**, because the
  desktop updater follows the repository's latest release.
- `mobile-v*` — Musify Android companion.

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
        +---> Sync Mobile Upstream Release ----> master ------------> mobile-v*
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

- GitHub Actions workflows for desktop packaging, Android packaging, and
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
