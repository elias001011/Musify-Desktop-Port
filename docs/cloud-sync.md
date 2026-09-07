# Optional Cloud Sync

Musify Desktop cloud sync is optional and disabled by default. It stores a
single latest backup snapshot for each passphrase. The snapshot includes the
same backed-up state used by local backup/restore: settings, playlists, liked
songs, recently played songs, and most-played metadata.

## Backend Contract

Build the app with:

```bash
flutter build linux --release --dart-define=MUSIFY_CLOUD_SYNC_URL=https://your-worker.example.com
flutter build windows --release --dart-define=MUSIFY_CLOUD_SYNC_URL=https://your-worker.example.com
```

The app calls:

- `GET /sync/<account-id>`: returns the latest JSON backup or `404`.
- `PUT /sync/<account-id>`: replaces the latest JSON backup.

Musify may gzip-compress large snapshots and store them inside a JSON envelope,
so the backend should treat the request body as opaque JSON and store it as-is.

`account-id` is a SHA-256 hash derived from the user's passphrase. Do not put a
GitHub token or any other write token in the app. Treat this endpoint as public:
the passphrase is the only thing separating one backup namespace from another.

## Security Model

Cloud Sync avoids embedding any GitHub or Cloudflare write token in the app. The
Worker is public, and the passphrase selects the backup namespace by deriving a
SHA-256 account id from:

```text
musify-cloud-sync-v1:<passphrase>
```

Use a strong passphrase. Anyone who can guess it can derive the same account id
and read or replace that backup.

The current payload is not end-to-end encrypted before being stored in
Cloudflare KV. Cloudflare and anyone with access to the Cloudflare account can
technically inspect the stored JSON. That is probably acceptable for music/app
state, but it should not be described as private encrypted storage.

Good next hardening step: derive an encryption key from the passphrase and
encrypt the snapshot client-side before upload. Keep the storage account id and
the encryption key as separate derivations so the Worker can route backups
without being able to read them.

## Limits

Cloudflare KV stores each value with a 25 MiB limit. The Worker example uses a
24 MB guard to stay under that limit. Musify may gzip-compress large snapshots
and wrap them in JSON before upload, which keeps normal large backups below the
limit.

If compressed backups start hitting 413 again, move the storage to Cloudflare R2
or split the snapshot into multiple keys.

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

## Deploying the Reference Worker

The Worker above can be deployed with `wrangler` (Cloudflare's CLI) in three
steps:

1. Create the KV namespace and note its id:

   ```bash
   npx wrangler kv namespace create MUSIFY_SYNC
   ```

2. Point a `wrangler.toml` at it:

   ```toml
   name = "musify-cloud-sync"
   main = "worker.js"
   compatibility_date = "2024-12-01"

   [[kv_namespaces]]
   binding = "MUSIFY_SYNC"
   id = "<namespace-id-from-step-1>"
   ```

3. Deploy and put the resulting URL in the build:

   ```bash
   npx wrangler deploy
   # then build the app with:
   # --dart-define=MUSIFY_CLOUD_SYNC_URL=https://musify-cloud-sync.<your-subdomain>.workers.dev
   ```

For GitHub Actions releases, set the same URL as the repository variable
`MUSIFY_CLOUD_SYNC_URL` (see `docs/maintenance.md`).

## Current Merge Behavior

Turning cloud sync on is an explicit choice, not an automatic overwrite:

- When you connect a passphrase or flip the cloud sync switch back on and a
  cloud backup already exists, Musify asks which copy to keep:
  - **Use cloud copy** downloads the cloud backup and replaces local data.
  - **Keep this device** uploads the current local data and replaces the cloud
    backup.
  - **Cancel** leaves both copies untouched and does not turn sync on.
- This is what makes "restore a local backup while sync is off, then turn sync
  on" safe: pick **Keep this device** and your restored data is pushed up
  instead of being overwritten by the old cloud snapshot.

Once sync is running, ongoing reconciliation is intentionally simple: latest
snapshot wins.

- On startup, Musify checks the cloud backup.
- If the cloud backup is newer than the local state, it is applied locally.
- If the local state is newer and automatic uploads are enabled, Musify replaces
  the cloud backup.
- If automatic uploads are disabled, startup still loads newer cloud data but
  does not upload local changes by itself. The user can manually upload or
  download from Settings.
- App offline mode pauses sync and cancels pending uploads.
- Leaving offline mode runs a normal sync first, so a newer cloud backup can be
  loaded before local changes are uploaded.

`offlineMode` is local-only and is not included in cloud backups. One device
going offline should not force the other devices offline when they sync.

Future versions can add field-level merge for playlist ordering and per-song
conflicts, but snapshot replacement is safer for the first desktop test.
