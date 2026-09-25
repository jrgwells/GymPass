# Security

## Threat model

Assets:

- PureGym email/PIN
- PureGym OAuth access and refresh tokens
- The raw access code (a bearer credential)
- The Wallet signing private key
- The per-pass Wallet authentication token
- APNs push tokens and device library identifiers
- Cloudflare tunnel credentials
- The database encryption key

Adversaries and surfaces:

- Other local users on the Mac
- Anything able to reach the public hostname
- Accidental leakage through logs, exports or the GUI
- The unofficial upstream API

## Controls

### Secrets at rest

- Secrets live in the macOS Keychain. The **agent is the only process that
  reads them**; the GUI sends credentials over the local control API once and
  never stores them.
- `applicationSupport`, the database and the control endpoint file use `0700`/`0600`
  permissions. The control endpoint file is written atomically with
  `completeFileProtection`.
- The published `.pkpass` archive and the raw access code are encrypted with
  AES-GCM (CryptoKit) under a Keychain-held 32-byte key. A `.pkpass` is signed,
  not encrypted, so storing the archive in plaintext would expose both the code
  and the Wallet token.

### Public attack surface

- The Wallet server binds to `127.0.0.1` only.
- The tunnel is intended to route only `/v1/*` and a short-lived `/install/*`.
  The control API listens on a **separate port** that is never tunneled, so a
  routing mistake cannot expose administration.
- Every Wallet route validates the exact protocol: pass-token authorization on
  the three pass-authenticated routes, bounded bodies, strict methods and
  numeric cursor comparison. Unauthorized requests get 401 **before** any pass
  bytes are disclosed.
- `/install/:token` uses a separate 32-byte capability token that expires,
  grants only pass download and never reveals the Wallet token. A HEAD or link
  preview does not consume it.
- Wallet requests cannot trigger PureGym calls or signing; the download route
  only serves the already-published archive.

### Local control API

- Loopback only, 32-byte random token, constant-time comparison.
- Typed `AgentRequest` enum; no shell text, no arbitrary file paths.
- The token rotates on every agent start.

### Cryptography

- `SecRandomCopyBytes` for all tokens and keys.
- AES-GCM via CryptoKit for at-rest encryption.
- CMS signing via Security.framework with SHA-256.
- No custom cryptography.

### Logging and diagnostics

- A central `Redactor` removes emails, tokens, `ApplePass`/`Bearer` values, the
  control token, `exerp:checkin:` codes, install paths, 64-byte hex strings and
  UUIDs. Diagnostics use it, so individual call sites cannot leak.
- Raw Wallet log submissions and `cloudflared` output are treated as untrusted
  and are not persisted or exported unfiltered.

### Abuse protection

- Strict routes and methods, body-size limits, per-IP soft rate limiting with
  generous allowances for legitimate Apple traffic, and no directory listing or
  debug pages.
- The agent's refresh engine honours server `Retry-After` and never polls
  aggressively beyond a bounded mode.

## Backups and restore

A restore must include, together, the database, the Keychain encryption key, the
pass signing identity, and the same pass type/serial and hostname. Restoring
only part of this leaves installed passes unable to update. Changing the pass
type or serial is a reinstallation, not a routine renewal.

## Not done

- The app is not sandboxed. A managed `cloudflared` child process plus a
  LaunchAgent agent and Keychain access are impractical under App Sandbox for
  v1; this is a deliberate trade-off.
- No telemetry, analytics or third-party crash reporting.
