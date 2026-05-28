<div align="center">
<img src="https://github.com/gokadzev/Musify/raw/master/.github/assets/Musify-banner.png" width="100%">

# Musify Cloud

Unofficial Musify mobile companion build for the desktop port, with optional
Cloud Sync.

Musify Cloud tracks [gokadzev/Musify](https://github.com/gokadzev/Musify), keeps
the upstream app experience, and adds a separate Android package, distinct icon,
our update channel, optional sync for multi-device use, and small quality of
life features that match the desktop port.

[![Stars](https://img.shields.io/github/stars/elias001011/Musify-Desktop-Port?style=flat-square&color=008F8C)](https://github.com/elias001011/Musify-Desktop-Port/stargazers)
[![Forks](https://img.shields.io/github/forks/elias001011/Musify-Desktop-Port?style=flat-square&color=008F8C)](https://github.com/elias001011/Musify-Desktop-Port/fork)
[![Downloads](https://img.shields.io/github/downloads/elias001011/Musify-Desktop-Port/total?style=flat-square&color=008F8C)](https://github.com/elias001011/Musify-Desktop-Port/releases)
[![GitHub release](https://img.shields.io/github/v/release/elias001011/Musify-Desktop-Port?color=008F8C)](https://github.com/elias001011/Musify-Desktop-Port/releases)
[![License](https://img.shields.io/github/license/gokadzev/Musify?color=D3BEAB)](LICENSE)

---

<a href="https://ko-fi.com/gokadzev" target="_blank" title="ko-fi">
  <img src="https://github.com/user-attachments/assets/1c204507-d124-4b34-878b-96c39c9bb3f8"  alt="ko-fi badge" style="width: 150px;">
</a>



---

## Features

<center>

Online song search with suggestions <br/>
Offline listening support <br/>
Import & export your data and never lose it <br/>
Add custom playlists with link <br/>
Optimized sound experience <br/>
SponsorBlock support <br/>
Lyrics support <br/>
No ads <br/>
No subscriptions <br/>
Built-in updater <br/>
Built-in equalizer with presets <br/>
21 supported languages <br/>
Material UI & accent colors & dynamic colors (Android 12+) <br/>
Optional Cloud Sync for settings, playlists, liked songs and play history <br/>
Automatic offline mode with repeated connectivity checks to avoid false offline flips <br/>
Separate package name, app name and icon so original Musify can stay installed <br/>

</center>


---

## Screenshots

| ![Screenshot 1](https://raw.githubusercontent.com/gokadzev/Musify/master/fastlane/metadata/android/en-US/images/phoneScreenshots/01.jpg) | ![Screenshot 2](https://raw.githubusercontent.com/gokadzev/Musify/master/fastlane/metadata/android/en-US/images/phoneScreenshots/02.jpg) | ![Screenshot 3](https://raw.githubusercontent.com/gokadzev/Musify/master/fastlane/metadata/android/en-US/images/phoneScreenshots/03.jpg) | ![Screenshot 4](https://raw.githubusercontent.com/gokadzev/Musify/master/fastlane/metadata/android/en-US/images/phoneScreenshots/04.jpg) |
|----------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|


---

## Download Musify Cloud


[<img src="https://github.com/gokadzev/Musify/raw/master/.github/assets/get-it-on-github.png" alt="Get it on Github" height="80">](https://github.com/elias001011/Musify-Desktop-Port/releases)

Original Musify downloads remain available from
[gokadzev/Musify](https://github.com/gokadzev/Musify/releases).

---

## Release Channels

This repository publishes two release families:

- `mobile-v*` is the Musify Cloud Android channel. These releases are not
  marked as GitHub Latest, so desktop builds do not accidentally detect Android
  packages as updates.
- `desktop-v*` is the desktop channel for Windows and Linux. Those releases are
  allowed to be GitHub Latest.

Musify Cloud only checks `mobile-v*` releases when looking for Android updates.

---

## Optional Cloud Sync

Cloud Sync is off by default. Users enable it in Settings with a passphrase.
Using the same passphrase on desktop and mobile loads the same cloud backup.
When automatic uploads are enabled, new local changes replace the previous cloud
backup after a short debounce.

Release builds read the backend URL from `MUSIFY_CLOUD_SYNC_URL`. See
[docs/cloud-sync.md](docs/cloud-sync.md) for the Cloudflare Worker/KV setup.

Current behavior is intentionally simple: the newest full backup wins. If a
device has newer local changes, it uploads them; if the cloud backup is newer,
the app loads it. See [docs/cloud-sync.md](docs/cloud-sync.md) for the security
model, limits and conflict notes.

---

## Automatic Offline Mode

Automatic offline mode is enabled by default and can be disabled in Settings.
Musify Cloud does not switch offline after one slow request: it checks multiple
known endpoints and requires repeated failures before enabling offline mode.

If the app enabled offline mode automatically, it also turns offline mode back
off after connectivity is confirmed again. Manual offline mode remains manual:
if the user turns offline mode on, the automatic checker will not turn it off.

This feature is local to the device. Cloud Sync does not copy the current
offline state between devices.

---

## Upstream Sync

The `mobile-cloud-sync` branch is kept close to
[gokadzev/Musify](https://github.com/gokadzev/Musify). Our changes are layered
on top: Cloud Sync, separate Android identity, update channel changes, release
workflows, automatic offline mode, and small compatibility fixes.

Automation checks upstream releases every six hours:

- if upstream publishes a new release, the workflow merges that upstream tag
  into `mobile-cloud-sync`;
- it runs dependency restore and `flutter analyze`;
- if validation passes, it dispatches the Android release workflow;
- the Android workflow publishes a new `mobile-v*` release without marking it
  as GitHub Latest.

If the upstream merge conflicts, GitHub Actions cannot safely guess the right
resolution. The workflow fails and opens an issue pointing to the failed run so
the conflict can be resolved manually.

See [docs/maintenance.md](docs/maintenance.md) for the release flow.

---

## Contributors

Special thanks to all contributors for their time and effort.

<a href="https://github.com/gokadzev/Musify/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=gokadzev/Musify" alt="Contributors"/>
</a>


---

## Contribute

Contributions are always welcome. Please read our [contributing guidelines](https://github.com/gokadzev/Musify/blob/master/CONTRIBUTING.md) before contributing.

---

## F.A.Q

You can see frequently asked questions and their answers [here](https://github.com/gokadzev/Musify/discussions/728).

---

## Credits

[Musify](https://github.com/Harsh-23/Musify) - Original inspiration for the concept and name. It is now completely reimplemented with new design and branding.


---

## License

```
Copyright © 2026 Valeri Gokadze

Musify is free software licensed under GPL v3.0. You may use, modify, and distribute
this software freely, but must keep the source code open and publicly available, retain
all copyright notices, disclose all changes made, and use the same GPL v3.0 license.

Prohibited: Closed-source distributions or commercial redistribution of modified versions.
```

See the [GNU General Public License](https://github.com/gokadzev/Musify/blob/master/LICENSE) for full details.

---

## Disclaimer

```
Musify and its contributors do not host, own, or distribute any copyrighted audio content.
The app provides access to content through plugins and external sources. All trademarks, songs, audio files, and related content remain the property of their respective owners and are protected by applicable copyright laws.
Included plugins are provided for interoperability and educational purposes only. Users are solely responsible for ensuring that their use of the app complies with local laws, copyright regulations, and the terms of service of the respective content providers.
The developers of Musify do not encourage or endorse copyright infringement and assume no liability for misuse of the software or third-party plugins.
```
---
