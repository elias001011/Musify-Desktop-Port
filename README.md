# Musify Desktop Port

Unofficial Windows and Linux desktop port of
[Musify](https://github.com/gokadzev/Musify).

Musify is created and maintained upstream by Valeri Gokadze and contributors at
[gokadzev/Musify](https://github.com/gokadzev/Musify). This repository keeps a
minimal desktop-focused port that tracks upstream releases and packages
ready-to-install builds for Windows and Linux.

The goal is not to fork Musify into a totally different app. The desktop branch
keeps startup and core app changes small, then layers a few companion features
that make the desktop and Musify Cloud mobile builds work better together.

## Downloads

Desktop releases are published here:

https://github.com/elias001011/Musify-Desktop-Port/releases

Available assets:

- `Musify-linux-x64.deb` for Debian/Ubuntu based distributions.
- `Musify-linux-x64.tar.gz` for portable Linux use.
- `Musify-windows-x64-setup.exe` for Windows installation.
- `Musify-windows-x64-portable.zip` for portable Windows use.
- `SHA256SUMS.txt` for artifact verification.

## Release Channels

This repository publishes two release families:

- `desktop-v*` is the Windows/Linux desktop channel. These releases are allowed
  to be GitHub Latest because the desktop updater follows them.
- `mobile-v*` is the Musify Cloud Android channel from the `mobile-cloud-sync`
  branch. Mobile releases are intentionally not marked as GitHub Latest, so the
  desktop app never sees Android APKs as updates.

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

## Extra Features

These features exist to make this desktop port and the Musify Cloud mobile build
feel like one optional multi-device experience:

- Desktop volume control. On Windows, Linux, and macOS, the miniplayer and the
  expanded now-playing action bar show a speaker button that opens an inline
  volume slider for the current audio player.
- Optional Cloud Sync. Users can enter the same passphrase on desktop and
  Musify Cloud mobile to load and replace the latest cloud backup for settings,
  playlists, liked songs, recently played songs, and most-played data.
- Automatic offline mode. The app can switch to offline mode after repeated
  confirmed connectivity failures and return online when connectivity is
  confirmed again. A Settings toggle disables this behavior.

Automatic offline mode is conservative on purpose: it checks multiple endpoints
and requires repeated failures before enabling offline mode, so a slow request
should not immediately cause a false offline flip.

## Downstream Adjustments

These are not intended as product features; they are maintenance and release
adjustments that keep the downstream port usable:

- GitHub Actions workflows for desktop packaging, mobile cloud packaging, and
  upstream sync.
- Workflow refs are written as `refs/heads/...` where possible, and upstream
  sync fetches only the selected upstream release tag. This avoids the upstream
  `master` tag being fetched into the job and making the local `master` branch
  name ambiguous.
- Release notes and updater channels are split so `desktop-v*` builds remain
  the desktop channel and `mobile-v*` builds remain the Musify Cloud Android
  channel.

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

## Updating From Upstream

The repository is prepared for automated maintenance with GitHub Actions:

- `Sync Upstream Release` checks the latest release from
  [gokadzev/Musify](https://github.com/gokadzev/Musify), merges it into this
  desktop port, runs Flutter dependency refresh, analysis, and a Linux smoke
  build, then dispatches the desktop release workflow.
- `Build Desktop Release` builds Linux and Windows packages and publishes a
  stable GitHub release. Existing releases are only overwritten when repair mode
  is explicitly enabled.

If GitHub Actions is unavailable on the account, the workflows remain ready and
can be enabled later without changing the repository layout. See
[docs/maintenance.md](docs/maintenance.md) for the manual and automated flows.

If the upstream merge conflicts, Actions cannot safely guess the right answer.
The sync workflow fails and opens an issue with a link to the run so the conflict
can be resolved manually.

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
