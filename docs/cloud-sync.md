# Optional Cloud Sync

Musify Cloud adds optional multi-device sync on top of upstream Musify. The
feature is disabled by default and only starts after the user enters a
passphrase in Settings.

The app stores one latest backup per passphrase. A new backup replaces the old
one. The snapshot includes the same backed-up state used by Musify's local
backup flow: settings, playlists, liked songs, recently played songs, and
most-played metadata.

## Security Model

Cloud Sync is designed to avoid shipping a write token in the app. The Worker is
public, and the user's passphrase selects the backup namespace by deriving a
SHA-256 account id from:

```text
musify-cloud-sync-v1:<passphrase>
```

That means a strong passphrase is important. Someone who can guess the
passphrase can derive the same account id and read or replace that backup.

The current implementation does not encrypt the backup payload before storing
it in Cloudflare KV. Cloudflare and anyone with access to the Cloudflare account
can technically read the stored JSON. This is acceptable for low-sensitivity
music/app state, but it is not private end-to-end encryption.

Good next hardening step: derive an encryption key from the passphrase and
encrypt the snapshot client-side before upload. The account id and encryption
key should be derived separately so the Worker can route the object without
being able to read it.

## Conflict Behavior

Sync is last-writer-wins at the full-backup level:

- startup downloads the cloud backup if it is newer than local state;
- local changes schedule an upload when automatic sync is enabled;
- manual upload replaces the previous cloud backup;
- manual load applies the current cloud backup to the device.
- app offline mode pauses sync and cancels pending uploads;
- leaving offline mode runs a normal sync first, so a newer cloud backup can be
  loaded before local changes are uploaded.

This keeps the first implementation simple and predictable, but it is not a
field-level merge. If two devices are edited offline at the same time, whichever
device uploads last becomes the cloud state. More advanced conflict handling
would need per-box or per-record timestamps.

`offlineMode` is local-only and is not included in cloud backups. One device
going offline should not force the other devices offline when they sync.

## Limits

Cloudflare KV stores each value with a 25 MiB limit. The Worker example uses a
24 MB guard to stay under that limit. Musify may gzip-compress large snapshots
and wrap them in JSON before upload, which keeps normal large backups below the
limit.

If compressed backups start hitting 413 again, move the storage to Cloudflare R2
or split the snapshot into multiple keys.

## Backend

Release builds need this Dart define:

```bash
flutter build apk --release --flavor github --dart-define=MUSIFY_CLOUD_SYNC_URL=https://your-worker.example.com
```

GitHub Actions reads the same value from the repository variable
`MUSIFY_CLOUD_SYNC_URL`.

The backend contract is intentionally tiny:

- `GET /sync/<account-id>` returns the latest JSON backup or `404`.
- `PUT /sync/<account-id>` replaces the latest JSON backup.

Musify may gzip-compress large snapshots and store them inside a JSON envelope,
so the backend should treat the request body as opaque JSON and store it as-is.

`account-id` is a SHA-256 hash derived from the user's passphrase. Do not embed
a GitHub token or any write token in the app. Treat the endpoint as public and
let the passphrase separate backup namespaces.

## Cloudflare Worker Example

Create a KV namespace and bind it as `MUSIFY_SYNC`, then deploy:

```js
const maxBackupBytes = 24_000_000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,PUT,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    const url = new URL(request.url);
    const match = url.pathname.match(/^\/sync\/([a-f0-9]{64})$/);

    if (!match) {
      return new Response("Not found", { status: 404, headers: corsHeaders });
    }

    const key = `backup:${match[1]}`;

    if (request.method === "GET") {
      const value = await env.MUSIFY_SYNC.get(key);
      if (!value) {
        return new Response("Not found", {
          status: 404,
          headers: corsHeaders,
        });
      }

      return new Response(value, {
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
        },
      });
    }

    if (request.method === "PUT") {
      const body = await request.text();
      const bodySize = new TextEncoder().encode(body).length;
      if (bodySize > maxBackupBytes) {
        return new Response("Backup too large", {
          status: 413,
          headers: corsHeaders,
        });
      }

      JSON.parse(body);
      await env.MUSIFY_SYNC.put(key, body);

      return new Response("OK", { headers: corsHeaders });
    }

    return new Response("Method not allowed", {
      status: 405,
      headers: corsHeaders,
    });
  },
};
```
