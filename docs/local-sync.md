# Local Sync

Local Sync keeps the Musify library the same on two or more devices by talking
to each other directly over the local network. There is no account, no server
and nothing leaves the Wi-Fi: each device with Local Sync turned on runs a tiny
HTTP server inside the app, and the others find it with a UDP broadcast.

The approach follows the peer-to-peer sync of
[Sonora](https://github.com/gmstyle/sonora) (discovery over UDP, pairing with a
PIN, a two-way merge over HTTP), adapted to Musify's Hive storage.

## Using it

1. On every device, open **Settings → Local sync** and turn on **Sync over
   local network**. The device becomes visible to other Musify devices on the
   same Wi-Fi.
2. On one device, open **Devices**. The other device shows up under **Other
   devices**; tap it.
3. The other device shows a 4-digit PIN. Type it on the first device. From now
   on the two are **paired** and either can sync with the other without a PIN.
4. The first sync runs right away. Afterwards, with **Automatic sync** on, each
   device syncs with every paired device it can see at startup, shortly after
   you change something, and every 30 minutes. You can also sync by hand from
   the Devices screen.

Both devices need Local Sync turned on: it is what makes them discoverable
and able to receive a library. Long-press a paired device to forget it.

## What gets synced

Everything in Musify's `user` storage that is library data:

| Data | Merge rule |
|---|---|
| Liked songs | union by song id |
| Online playlists added by link (`playlists`) and liked playlists (`likedPlaylists`) | union by id |
| Custom playlists (including those inside folders) | matched by id, then by title; songs merged (see conflicts below) |
| Playlist folders | matched by id, then by name; new playlists land in the matching folder, folders are created when missing |
| Pinned playlists | union, up to the pin limit |
| Recently played | union by song id; the most recent play and the higher play count win |
| Liked radio stations, search history | union |

Not synced: settings (theme, quality, shortcuts, interface scale — desktop and
phone differ on purpose), offline downloads, the listening recap statistics,
and offline mode.

**Deletions do not propagate.** The merge only adds. Remove a song from a
playlist on one device and the next sync brings it back from the other, unless
you remove it there too. This is the same trade-off Sonora makes: an additive
merge can run in any direction, at any time, and never lose anything.

### Same-name playlists

Custom playlists get a random id when they are created, so a playlist created
on one device and synced keeps that id everywhere and is always recognised as
the same playlist. The **Same-name playlists** setting decides what happens
when each device created its *own* playlist with the same title:

- **Merge songs** (default): they become one playlist with the songs of both.
- **Keep both playlists**: both stay, one per original device.
- **Other device wins**: the incoming playlist replaces the songs of the local
  one with the same name. Note that the merge runs on both ends of a sync, so
  the device that *starts* the sync effectively wins.

## How a sync works

```
Device A (starts the sync)                 Device B
        |                                     |
        |-- UDP MUSIFY_DISCOVERY_REQUEST ---->|  (broadcast, port 53531)
        |<-- MUSIFY_DISCOVERY_RESPONSE;name;port;deviceId
        |                                     |
        |-- POST /api/sync/pair-request ----->|  first time only:
        |<-- pairing_started                  |  B shows a PIN
        |-- POST /api/sync/pair-verify (PIN)->|
        |<-- paired + B's device id           |  both remember each other
        |                                     |
        |-- POST /api/sync/merge (A library)->|  B merges A into itself
        |<-- B's merged library + stats       |
        |   A merges it into itself           |
```

After one round trip both libraries are identical. Each device has a random
device id (stored in the `userNoBackup` box, so backups do not carry it) and a
list of paired device ids. A merge request from an unpaired id is refused with
`403`; the sending device then drops the pairing and asks for a PIN again.

The HTTP server binds a random free port on all IPv4 interfaces. Discovery
listens on UDP port `53531`; the scan sends to `255.255.255.255` and to the
`/24` broadcast of every interface, so a desktop with several networks still
reaches the Wi-Fi the phone is on. A device whose discovery port is already
taken (another Musify instance on the same machine) still accepts syncs but
cannot be found by a scan.

### Security model

- Pairing needs physical access to both devices: the PIN is only shown on the
  device being paired to, expires after 60 seconds, and a wrong PIN is refused.
- After pairing, the device id acts as a bearer token on the local network.
  Anyone on the same network who learns a paired id could push a library. That
  is acceptable for a home Wi-Fi and not for a hostile one; forget devices you
  no longer use.
- Traffic is plain HTTP inside the local network. Nothing is uploaded anywhere.

## Platform notes

- **Android** needs the multicast lock (`CHANGE_WIFI_MULTICAST_STATE`) to
  receive broadcasts; the app acquires it while Local Sync is on. Some phones
  drop UDP broadcasts on battery-saver Wi-Fi; scan again or move closer to the
  router. The sync server only runs while the app is alive.
- **Windows** asks once, on the first start with Local Sync on, whether Musify
  may accept connections on private networks. Say yes, or discovery will fail.
- **Linux** firewalls (ufw, firewalld) may need UDP `53531` and the app's TCP
  port allowed on the LAN zone.
- Guest Wi-Fi networks and "AP isolation" block device-to-device traffic
  entirely; both devices must be on the same regular network.

## Code map

- `lib/services/local_sync_service.dart` — server, discovery, pairing, the
  client side of a sync and the automatic triggers. `LocalSyncService.instance`
  is started from `main.dart`, which also shows the incoming-PIN dialog.
- `lib/services/library_merge_service.dart` — `exportLibrary()` and
  `mergeLibrary()`, the payload format and every merge rule above.
- `lib/screens/local_sync_page.dart` — the Devices screen.
- `lib/screens/settings_page.dart` — the **Local sync** section.
- `test/library_merge_service_test.dart`, `test/local_sync_service_test.dart`
  — merge rules and the pairing handshake over loopback.

Wire format (`schemaVersion: 1`): a JSON object with one key per storage key
above. `DateTime` values are wrapped as `{"__musifyType": "DateTime", "value":
"<ISO-8601 UTC>"}` because JSON has no date type.
