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

`account-id` is a SHA-256 hash derived from the user's passphrase. Do not put a
GitHub token or any other write token in the app. Treat this endpoint as public:
the passphrase is the only thing separating one backup namespace from another.

## Cloudflare Worker Example

Create a KV namespace and bind it as `MUSIFY_SYNC`, then deploy:

```js
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
      if (body.length > 5_000_000) {
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

## Current Merge Behavior

This first version is intentionally simple: latest snapshot wins.

- On startup, Musify checks the cloud backup.
- If the cloud backup is newer than the local state, it is applied locally.
- If the local state is newer and automatic uploads are enabled, Musify replaces
  the cloud backup.
- If automatic uploads are disabled, startup still loads newer cloud data but
  does not upload local changes by itself. The user can manually upload or
  download from Settings.

Future versions can add field-level merge for playlist ordering and per-song
conflicts, but snapshot replacement is safer for the first desktop test.
