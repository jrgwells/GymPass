# GymPass architecture

## Processes

```
┌────────────────────────────┐        loopback HTTP + token        ┌──────────────────────────────┐
│  GymPass.app (SwiftUI)     │ ──────────────────────────────────▶ │  GymPassAgent (LaunchAgent)  │
│  dashboard, wallet, etc.   │ ◀────────────────────────────────── │  owns all state + secrets    │
└────────────────────────────┘          status / activity          └───────────────┬──────────────┘
                                                                                   │
                                       ┌───────────────────────────────────────────┼──────────────────────────┐
                                       ▼                                           ▼                          ▼
                              PureGym (auth + QR)                        Apple Wallet update protocol   Cloudflare Tunnel
                                                                        (APNs + device registrations)   (named tunnel → /v1, /install)
```

- **GymPassAgent** is a per-user LaunchAgent. It continues running when the GUI
  window is closed and when the GUI process quits. It is the single owner of the
  database, the Keychain items, the Wallet server and the tunnel.
- **GymPass** (GUI) is a thin client. It never touches the database or Keychain.

## Control API

Loopback only, never tunneled. Bound to `127.0.0.1:8755` (demo: `18955`).

- `GET /health`
- `GET /control/status` — `StatusSnapshot`
- `POST /control/request` — a typed `AgentRequest` → `AgentResponse`
- `GET /control/activity?limit=` — `[ActivityEvent]`

Authentication uses a 32-byte random token written to
`~/Library/Application Support/GymPass/control.json` with `0600` permissions.
The endpoint file is re-read on each GUI poll so agent restarts are picked up.
No arbitrary commands or file paths cross this boundary.

## Wallet web service

Loopback only; the tunnel routes only `/v1/*` and `/install/*` to it.

| Method and path | Auth | Result |
|---|---|---|
| `POST /v1/devices/:dli/registrations/:pti/:serial` | `ApplePass <token>` | 201 new, 200 existing |
| `DELETE /v1/devices/:dli/registrations/:pti/:serial` | `ApplePass <token>` | 200, idempotent |
| `GET /v1/devices/:dli/registrations/:pti?passesUpdatedSince=` | device id is the secret | 200 list or 204 |
| `GET /v1/passes/:pti/:serial` | `ApplePass <token>` | 200 pkpass, 304 or 401 |
| `POST /v1/log` | none | 200, untrusted, not persisted |
| `GET /install/:token` | capability token | HTML install page |
| `GET /install/:token/pass` | capability token | short-lived `.pkpass` download |

The update cursor is a monotonic integer revision compared numerically.
`If-Modified-Since` is handled separately from the update cursor; a same-second
ambiguity returns 200 rather than a wrong 304.

## Storage

SQLite via GRDB at `~/Library/Application Support/GymPass/gympass.sqlite`.

- `wallet_registration` — device/pass registrations, token generation
- `wallet_pass_state` — published revision, encrypted `.pkpass` archive
- `qr_state` — encrypted current access code, expiry metadata
- `notification_outbox` — durable APNs work
- `activity_event` — bounded human-readable history
- `app_config` — non-secret configuration

The `.pkpass` archive and the access code are encrypted with AES-GCM
(CryptoKit) using a key stored in the Keychain.

## Publication transaction

```
fetch QR → validate → compare content identity
        → build + sign + verify archive
        → one DB transaction: archive + revision + timestamps + outbox rows
        → send APNs
        → retry pending outbox work
```

If any preparation step fails, the previous published archive is untouched. A
failed push never destroys pass state; devices fetch the newest revision the
next time they check.

## Refresh strategy

`RefreshEngine` coalesces concurrent refreshes and computes the next check from
observed metadata, failures and policy:

- `conservative` — refresh near the reported expiry margin
- `balanced` (default) — honour the refresh hint but never below a floor
- `aggressive` — bounded high-frequency burst

Failures use exponential backoff with jitter. Server rate limits and
`Retry-After` always win, including over manual refreshes. The raw access code
is never logged.

## Background service lifecycle

| Mac state | Behaviour |
|---|---|
| Window closed | Agent continues |
| GUI quits | Agent and tunnel continue |
| Screen locked | Agent continues |
| System asleep | No continuous serving; recovers on wake |
| Logged out / reboot before login | Per-user agent unavailable |
| Approval disabled | Surfaced in the UI with a Settings link |

Installation uses `launchctl` and a `~/Library/LaunchAgents` plist. A
Team-ID-signed build can switch to `SMAppService` with the embedded plist at
`Contents/Library/LaunchAgents/com.jackwells.gympass.agent.plist`.
