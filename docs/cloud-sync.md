# Optional Cloud Sync

Musify Cloud adds optional multi-device sync on top of upstream Musify. The
feature is disabled by default and only starts after the user enters a
passphrase in Settings.

The app stores one latest backup per passphrase. A new backup replaces the old
one. The snapshot includes the same backed-up state used by Musify's local
backup flow: settings, playlists, liked songs, recently played songs, and
most-played metadata.

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

`account-id` is a SHA-256 hash derived from the user's passphrase. Do not embed
a GitHub token or any write token in the app. Treat the endpoint as public and
let the passphrase separate backup namespaces.

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
