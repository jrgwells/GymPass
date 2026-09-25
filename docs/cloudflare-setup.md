# Cloudflare Tunnel setup

Automatic Wallet updates need a stable public HTTPS address for the Wallet
update API. GymPass uses an outbound Cloudflare Tunnel, so no router port
forwarding or inbound firewall rule is needed.

> Do not use a Quick Tunnel (`trycloudflare.com`) as the permanent address. It
> changes on every restart and would be embedded in installed passes. Use a
> named tunnel with your own hostname.

## Prerequisites

- A Cloudflare account and a domain on Cloudflare.
- `cloudflared` installed, e.g. `brew install cloudflared`.

## Steps

1. Authenticate and create a named tunnel:

   ```bash
   cloudflared tunnel login
   cloudflared tunnel create gympass
   ```

2. Route a hostname to it (example):

   ```bash
   cloudflared tunnel route dns gympass wallet.example.com
   ```

3. Get a tunnel token for token-based runs:
   Cloudflare dashboard → **Zero Trust → Networks → Tunnels → your tunnel →
   Configure → Docker** and copy the token. Or use the credentials JSON.

4. In GymPass **Settings → Connectivity**:
   - Provider: **Cloudflare Tunnel**
   - Public hostname: `wallet.example.com`
   - Paste the tunnel token
   - **Apply**, then **Test Connection**.

## How GymPass exposes only what it should

The Wallet server listens on `127.0.0.1:8754`. Configure the tunnel's public
hostname ingress to route only:

```
wallet.example.com
  └── path /v1/*        → http://127.0.0.1:8754
  └── path /install/*   → http://127.0.0.1:8754
  (everything else → 404)
```

The GUI control API listens on a **separate** loopback port (`8755`) that is
never part of the tunnel. In the dashboard’s public-hostname ingress rules, do
not add a catch-all path that reaches any other route.

Do not put Cloudflare Access, a CAPTCHA or any browser challenge in front of
`/v1/*`; Apple Wallet cannot complete an interactive login.

## Verify

- **Diagnostics → Test Remote Access** should report *Reachable* with a latency.
- Open `https://wallet.example.com/health` from a browser; it should return
  `{"status":"ok"}`. This route is intentionally non-secret and is used only for
  the reachability test.
- Confirm `https://wallet.example.com/control/status` returns 404.

## Changing hostname later

A hostname change is a migration. Installed passes keep the old `webServiceURL`
until they are updated. Keep the old hostname working until devices have fetched
at least one update, or reinstall the pass.
