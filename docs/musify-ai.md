# Musify AI

Experimental and personal. Musify Cloud plus an assistant that can drive the
app: search, play a song or a whole album, build playlists, start a station
from a track, manage the library and downloads, read listening history, open
screens.

Treat it as a side experiment rather than a supported product. If you just want
sync, install Musify Cloud; Musify AI is a superset, so there is no reason to
run both.

## What it is

Musify AI starts from the Musify Cloud branch and adds a built-in assistant on
top. The assistant is exposed through the same app UI you already use for
search, playback, playlists, downloads and settings. It can:

- search and play a song, album or artist
- queue and build playlists
- start a station from a track
- manage the library and downloads
- read listening history
- open relevant screens in the app

It needs an API key from a provider you choose (Groq, Gemini or OpenRouter).

## Why it exists

Musify AI exists because the same person who keeps the desktop port also wants
an assistant-driven way to use Musify on the phone. It is not intended as a
public release channel. The branch is here so the desktop port's sync flow can
reach an AI build the same way it reaches Musify Cloud, but the build itself is
personal and experimental.

## Why it tracks Musify Cloud

Musify AI tracks Musify Cloud rather than upstream directly. Cloud already
resolved the upstream merge and passed its own checks, so the AI branch only
ever faces one kind of conflict instead of two: Cloud vs AI.

Every sync merges plainly and stops on conflict. Earlier versions retried with
`-X ours`/`-X theirs`, which reported success while keeping fork code that
called a refactored upstream API. Nothing is pushed unless `flutter analyze` is
clean.

## Privacy

Its API keys never leave the device. They are excluded from Cloud Sync, whose
payload is not encrypted, and Musify AI uses a separate sync namespace, so it
never reads or overwrites a Musify Cloud backup.

## Releases

Musify AI uses its own release channel (`musifyai-v*`) and its own Android
package id. It is deliberately never marked as GitHub Latest.

## Docs

- Cloud Sync setup: [docs/cloud-sync.md](../docs/cloud-sync.md)
- Release and maintenance flow: [docs/maintenance.md](../docs/maintenance.md)
- README overview: [README.md](../README.md)
