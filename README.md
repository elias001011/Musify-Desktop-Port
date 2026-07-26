# Musify Desktop Port

Unofficial downstream builds of
[Musify](https://github.com/gokadzev/Musify), by Valeri Gokadze and
contributors. This repository packages **three products** from one codebase:
the Windows/Linux desktop port, an Android build with cloud sync, and an Android
build with a built-in AI assistant.

<!-- download-counts:start -->
[![Musify Desktop Port downloads](https://img.shields.io/badge/desktop%20downloads-42-2F6FE0?style=for-the-badge&logo=github)](https://github.com/elias001011/Musify-Desktop-Port/releases)
[![Musify Cloud downloads](https://img.shields.io/badge/Musify%20Cloud-3-006A71?style=for-the-badge)](https://github.com/elias001011/Musify-Desktop-Port/releases)
[![Musify AI downloads](https://img.shields.io/badge/Musify%20AI-0-2F4FE0?style=for-the-badge)](https://github.com/elias001011/Musify-Desktop-Port/releases)

<sub>45 downloads across every release of all three products. Updated daily.</sub>
<!-- download-counts:end -->

None of this is an official Musify release channel. The goal is not to fork
Musify into a different app: each product keeps the upstream app intact and adds
one layer on top.

## The three products

|  | **Musify Desktop Port** | **Musify Cloud** | **Musify AI** |
|---|---|---|---|
| Platform | Windows, Linux | Android | Android |
| What it adds | desktop packaging and playback | cloud sync | cloud sync **and** the AI assistant |
| Release tags | `desktop-v*` | `mobile-v*` | `musifyai-v*` |
| Downloads | `.deb`, `.tar.gz`, `setup.exe`, portable `.zip` | `MusifyCloud.apk` | `MusifyAI.apk` |
| Android app id | — | `com.elias001011.musifycloud` | `com.elias001011.musifyai` |
| Branch | `master` | `mobile-cloud-sync` | `feature/musify-ai` |
| Tracks | upstream releases | upstream releases | Musify Cloud releases |

The two Android builds have **different application ids**, so they install side
by side, each with its own icon, name and data. Musify AI is a superset of Musify
Cloud: everything Cloud does, plus the assistant. If you want the assistant,
install Musify AI and not both.

### Musify Desktop Port — Windows and Linux

The original app made to run on the desktop: Flutter desktop targets,
`just_audio` playback through `media_kit`, Linux packaging with a `libmpv`
dependency, a Windows installer and portable zip, and desktop-safe guards where
upstream calls Android-only APIs. It also adds a speaker button with an inline
volume slider to the miniplayer and the expanded player, which a phone does not
need.

Assets on each `desktop-v*` release:

- `Musify-linux-x64.deb` for Debian/Ubuntu based distributions.
- `Musify-linux-x64.tar.gz` for portable Linux use.
- `Musify-windows-x64-setup.exe` for Windows installation.
- `Musify-windows-x64-portable.zip` for portable Windows use.
- `SHA256SUMS.txt` for artifact verification.

### Musify Cloud — Android with cloud sync

Original mobile Musify plus optional Cloud Sync: enter the same passphrase on
two devices and your settings, playlists, liked songs, recently played and
most-played data follow you. Off by default.

Sync is last-writer-wins on a whole backup, not a per-song merge, and the
backend stores JSON in Cloudflare KV without end-to-end encryption. See
[docs/cloud-sync.md](docs/cloud-sync.md) for the security model and its limits.

### Musify AI — Android with an assistant

Musify Cloud plus an assistant that can actually drive the app: search, play a
song or a whole album, build playlists, start a station from a track, manage
your library and downloads, read your listening history, and open screens for
you. It needs an API key from a provider you choose (Groq, Gemini or
OpenRouter).

**Your API keys never leave the device.** They are excluded from Cloud Sync,
whose payload is not encrypted. Musify AI also uses its own sync namespace, so it
never reads or overwrites a Musify Cloud backup.

See [docs/musify-ai.md](docs/musify-ai.md) for the provider setup, the full tool
list and what is planned next.

## Release channels

Three families, published to the same release list:

- `desktop-v*` — the Windows/Linux channel. These are allowed to be GitHub
  **Latest**, because the desktop updater follows the repository's latest
  release.
- `mobile-v*` — the Musify Cloud Android channel.
- `musifyai-v*` — the Musify AI Android channel.

The two Android channels are deliberately **never** marked Latest, and the
release workflows re-pin the newest `desktop-v*` release afterwards. Without
that, GitHub promotes whichever release was published most recently and the
desktop updater starts offering people an APK.

Each app only looks at its own channel: the updater filters releases by tag
prefix, so a desktop install never sees an Android build and vice versa.

## How the three stay in sync

```
gokadzev/Musify publishes a release
        |
        +---> Sync Desktop Upstream Release ---> master ---------> desktop-v*
        |
        +---> Sync Mobile Upstream Release ----> mobile-cloud-sync -> mobile-v*
                                                        |
                                                        v
                                        Sync Musify AI from Musify Cloud
                                                        |
                                                        v
                                        feature/musify-ai ------> musifyai-v*
```

Musify AI tracks Musify Cloud rather than upstream directly: Cloud has already
resolved the upstream merge and passed its own checks, so the AI branch only
ever faces one kind of conflict instead of two.

Every sync merges plainly and **stops on conflict** — earlier versions retried
with `-X ours`/`-X theirs`, which reported success while keeping fork code that
called a refactored upstream API. Nothing is pushed unless `flutter analyze` is
clean, and the release build is dispatched against that exact validated commit.
When a merge does conflict, the run lists the files and fails; Actions cannot
guess the right answer.

See [docs/maintenance.md](docs/maintenance.md) for the desktop and Cloud flows
and [docs/musify-ai.md](docs/musify-ai.md) for the AI branch.

## Minimal Desktop Startup

The desktop port keeps the upstream app close to original Musify and only adds
the compatibility pieces needed for desktop startup and daily use:

- Flutter Windows and Linux desktop targets.
- `just_audio` desktop playback through `media_kit`.
- Linux package metadata with `libmpv` runtime dependency.
- Windows portable ZIP and Inno Setup installer packaging.
- Desktop-safe guards for Android-only equalizer and mobile sharing-intent APIs.
- Desktop updater that checks this repository's `desktop-v*` releases instead
  of the upstream Android release feed.

## Downstream Adjustments

These are not intended as product features; they are maintenance and release
adjustments that keep the downstream port usable:

- GitHub Actions workflows for desktop packaging, Musify Cloud packaging,
  Musify AI packaging, and the syncs between all of them.
- Workflow refs are written as `refs/heads/...` where possible, and upstream
  sync fetches only the selected upstream release tag. This avoids the upstream
  `master` tag being fetched into the job and making the local `master` branch
  name ambiguous.

## Optional Cloud Sync

Cloud sync is off by default. Users enable it from Settings with a passphrase.
Release builds need a backend URL compiled in with:

```bash
flutter build linux --release --dart-define=MUSIFY_CLOUD_SYNC_URL=https://example.com
```

For GitHub Actions releases, set the repository variable
`MUSIFY_CLOUD_SYNC_URL`. If the value is empty, the app still builds and the
sync UI explains that no backend is configured.

Current sync behavior is last-writer-wins at the full-backup level. The newest
snapshot replaces the older one; it is not a per-song or per-playlist merge.
The current backend stores JSON in Cloudflare KV and is not end-to-end
encrypted. See [docs/cloud-sync.md](docs/cloud-sync.md) for the security model
and limits.

Musify AI uses a separate sync namespace, so its backups and Musify Cloud's
never touch each other, and it keeps AI provider API keys out of the payload
entirely.

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
