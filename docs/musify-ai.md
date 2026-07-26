# Musify AI

Musify AI is Musify Cloud plus a built-in assistant. Everything Cloud does —
playback, library, offline, Cloud Sync — behaves the same here; the difference is
the assistant tab and its own product identity.

This file is the AI branch's own documentation. `docs/maintenance.md` and
`docs/SYNC_GUIDE.md` describe the Cloud and desktop branches and are deliberately
left untouched on this branch so that syncing from Cloud never conflicts on them.

## Branch and identity

| | Musify Cloud | Musify AI |
|---|---|---|
| Branch | `mobile-cloud-sync` | `feature/musify-ai` |
| Android id | `com.elias001011.musifycloud` | `com.elias001011.musifyai` |
| App name | Musify Cloud | Musify AI |
| Deep link | `musifycloud://` | `musifyai://` |
| Icon colour | `#006A71` teal | `#2F4FE0` indigo |
| Release tags | `mobile-v*` | `musifyai-v*` |
| APK assets | `MusifyCloud*.apk` | `MusifyAI*.apk` |
| Cloud Sync namespace | `musify-cloud-sync-v1:` | `musify-ai-sync-v1:` |

The different `applicationId` is what lets both be installed side by side. The
different Cloud Sync namespace is what stops them from overwriting each other's
backup: the two builds do not have the same settings shape, and a snapshot
restore deletes keys that are not in the snapshot.

The version number tracks upstream Musify, same as Cloud, so `musifyai-v10.1.1`
is built from upstream 10.1.1.

### Icons

There is no vector master for the app icon; the bitmaps were hand-edited when
Cloud forked from upstream. `tools/recolor_icons.py` reproduces the Musify AI
recolour from the Cloud artwork:

```bash
python3 tools/recolor_icons.py          # rewrite the bitmaps
python3 tools/recolor_icons.py --check  # verify only, non-zero exit on failure
```

Only the five legacy square launcher icons actually carry the brand fill. The
adaptive and notification glyphs are white-on-alpha and take their colour from
`@color/ic_launcher_background` in `android/app/src/main/res/values/colors.xml`,
and the splash background bitmaps are neutral greys. The script documents which
files it deliberately skips and why.

## Your API keys stay on the device

Musify AI needs a provider API key (Groq, Gemini or OpenRouter) to work. Those
keys live in the `aiProviders` settings key, which is on the Cloud Sync
**local-only** list: it is never uploaded, even with Cloud Sync enabled. The sync
payload is not encrypted, so a synced key would be readable on the server.

The consequence is that a new device needs its keys entered again. Everything
else about the assistant — its name, provider order, per-tool switches — does
sync.

## Release flow

```
Musify Cloud publishes mobile-v<version>
        |
        v
sync_ai_from_cloud.yml   (release: published, gated to mobile-v* tags)
  merge mobile-cloud-sync -> feature/musify-ai   (plain merge; conflicts abort)
  refresh version.dart and pubspec.lock
  flutter analyze                                (gate: nothing is pushed if it fails)
  push feature/musify-ai
        |
        v
musifyai_release.yml     (dispatched pinned to the exact validated SHA)
  build arm64 + universal APK, publish musifyai-v<version>
  make_latest=false, then re-pin the newest desktop-v* release as Latest
```

Notes on the parts that are easy to get wrong:

- The `release` event has **no tag filter** — there is no `tags:` key for it the
  way there is for `push`. Every published release starts the workflow, and the
  first step is a gate that exits early unless the tag starts with `mobile-v`.
- `release: published` only fires for workflows on the repository's **default
  branch**, so `sync_ai_from_cloud.yml` and `musifyai_release.yml` are also
  committed to `master`. That is the same reason all the other workflow files
  exist on every branch. They are inert on `master`: it never carries a
  `musifyai-v*` tag.
- Latest belongs to the `desktop-v*` channel. `make_latest=false` only unpins the
  release being published; GitHub then promotes whatever non-prerelease release
  is newest, which would be the AI build. The release workflow therefore re-pins
  the newest `desktop-v*` release afterwards.

### Doing it by hand

```bash
git checkout feature/musify-ai
git merge --no-edit mobile-cloud-sync
flutter pub get && flutter analyze          # never push without this
git push origin feature/musify-ai

gh workflow run musifyai_release.yml \
  --ref refs/heads/feature/musify-ai \
  -f version="10.1.1" \
  -f source_ref="$(git rev-parse HEAD)" \
  -f repair_existing_release=false
```

There is no Java in the usual dev environment here, so an APK cannot be built
locally. `musifyai_debug.yml` builds a debug APK artifact for smoke-testing
before cutting a release.

### The five inherited workflow files

`desktop_release.yml`, `mobile_release.yml`, `mobile_debug.yml`,
`sync_desktop_upstream_release.yml` and `sync_mobile_upstream_release.yml` are
byte-identical to their `mobile-cloud-sync` versions and **must be left that
way on this branch**. They are inert here (their triggers key off branches and
tag prefixes this branch never produces), and editing them would turn every
future Cloud sync into a conflict on files this branch does not even use.

## The assistant

Settings live under Settings → Musify AI: enable/disable, assistant name,
provider order with API keys and model per provider, and a switch per tool.

Providers are tried in order, and each provider's keys are tried in turn, so a
rate-limited key falls through to the next one. Groq and OpenRouter stream the
final answer; Gemini does not (its endpoint is a reverse-engineered one and is
kept on the simpler non-streaming path).

## Future work

Capabilities that the app already has the plumbing for, and that the assistant
does not use yet:

- **Charts, moods and genres.** `YoutubeHttpClient.sendPost('browse', ...)` in
  the vendored `youtube_explode_dart` reaches any InnerTube endpoint, so
  `FEmusic_charts` and `FEmusic_moods_and_genres` are available with new parsing
  in `packages/youtube_music_explode_dart/lib/src/music_client.dart`.
- **Real mix radio.** `sendPost('next', {playlistId: 'RDAMVM<videoId>'})`, or the
  cheaper `RelatedVideosList.nextPage()` for an effectively infinite related
  feed.
- **Richer search filters.** `TypeFilters.channel` and `UploadDateFilter.*` are
  plumbed through `SearchClient.search(query, filter:)` and unused.
- **Artist metadata.** `Channel.subscribersCount` and
  `ChannelClient.getAboutPage` (bio, country, links, total views) are fetched
  nowhere.
- **Per-artist listening stats.** `listening_stats_service.dart` aggregates per
  song only; artist totals are currently derived from the top songs sample.
- **Localised assistant strings.** The assistant's UI strings are hardcoded
  Portuguese; they should move into the ARB files with the rest of the app.
