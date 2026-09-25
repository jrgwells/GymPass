# GymPass

GymPass keeps your PureGym access code up to date in Apple Wallet, automatically,
on iPhone and Apple Watch.

It is a native macOS application: a SwiftUI control panel plus a bundled
background service. The service authenticates with PureGym, retrieves the
current access code, generates and signs a Wallet `.pkpass`, serves Apple's
Wallet update protocol over HTTPS (via Cloudflare Tunnel), and notifies your
devices with Apple Push when the code changes.

> GymPass uses PureGym's unofficial API. It is intended for personal use and may
> break without notice. All PureGym-specific behaviour is isolated behind a
> client abstraction so endpoint changes are contained.

## Status at a glance

| Area | State |
|---|---|
| PureGym client, QR retrieval, refresh engine | Implemented, mock-tested, not live-tested here |
| Wallet pass build / sign / verify (native CMS) | Implemented, tested with a test identity |
| Wallet web-service protocol | Implemented, tested end to end |
| APNs Wallet notifications + durable outbox | Implemented, mock-tested; header policy needs a real pass |
| Background agent, control API, installer | Implemented, verified running in demo mode |
| Cloudflare Tunnel supervision | Implemented; needs your domain/account |
| SwiftUI dashboard, wallet, activity, diagnostics, settings, onboarding, menu bar | Implemented, launches from the packaged app |
| Real `.pkpass` installation on iPhone/Watch | Requires your Apple Developer Pass Type ID certificate |

See `docs/final-review.md` for the full evidence matrix.

## Requirements

- macOS 26 or later (Apple Silicon tested)
- Swift 6.3 toolchain. **Full Xcode is not required** — CommandLineTools is enough.
- `cloudflared` for remote updates (Homebrew: `brew install cloudflared`)
- Your own:
  - PureGym account (email + PIN)
  - Apple Developer Pass Type ID certificate and private key (`.p12`)
  - Cloudflare account with a domain, for a stable tunnel hostname

## Build

```bash
git clone <repo> GymPass && cd GymPass

# Build everything
swift build

# Run the test suite (custom runner; see docs/development.md)
swift run GymPassTests

# Assemble and sign GymPass.app (ad-hoc by default)
./scripts/build-app.sh
open dist/GymPass.app
```

To sign with a Developer ID:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
```

## First run in demo mode (no credentials needed)

Demo mode simulates PureGym, Apple Push and the tunnel so you can explore the
whole app.

```bash
swift run GymPassAgent --demo
# then, in another terminal
swift run GymPassApp
```

The GUI discovers the agent by reading
`~/Library/Application Support/GymPass/control.json`. Install the signing
certificate from `Tests/Fixtures/test-identity.p12` (password `gympass-test`) to
exercise pass generation. This test certificate is **not** trusted by Apple and
cannot produce an installable pass.

## Configuring real credentials

1. **PureGym** — in the setup wizard, enter your email and PIN.
2. **Apple Wallet** — import your Pass Type ID `.p12`. GymPass derives the Pass
   Type ID and Team ID from the certificate and runs a signing self-test.
3. **Automatic updates** — configure a Cloudflare named tunnel and public
   hostname (see `docs/cloudflare-setup.md`).
4. **Install the pass** — use the installation code shown in the app, scanned
   with your iPhone.

## Architecture

```
GymPass.app
├── GymPass (SwiftUI control panel)
│   └── talks to the agent over a loopback, token-authenticated control API
└── GymPassAgent (background service, registered as a per-user LaunchAgent)
    ├── PureGymClient         authentication, QR retrieval, rate limiting
    ├── RefreshEngine         scheduling, coalescing, atomic publication
    ├── WalletPassService     pass.json + assets + manifest + CMS signature
    ├── WalletHTTPServer      Apple Wallet update protocol (loopback, tunneled)
    ├── ControlServer         local control API (never tunneled)
    ├── APNsClient            Wallet update notifications
    ├── CloudflareTunnelProvider  supervised outbound tunnel
    ├── DatabaseManager       SQLite (GRDB)
    └── KeychainStore         secrets and signing identity
```

See `docs/architecture.md`.

## Security summary

- Secrets live in the macOS Keychain. The agent is the only process that reads them.
- The Wallet archive and raw access code are encrypted at rest (AES-GCM).
- The Wallet server binds to loopback only; the tunnel exposes just `/v1/*` and
  a short-lived `/install/*` route.
- The control API is loopback-only and token-authenticated; it is never tunneled.
- Logs and diagnostics are centrally redacted.

See `docs/security.md`.

## Documentation

- `docs/architecture.md` — processes, data flow, storage, IPC
- `docs/research.md` — Apple Wallet protocol and PureGym API findings
- `docs/implementation-plan.md` — the plan this was built from
- `docs/security.md` — threat model and mitigations
- `docs/wallet-setup.md` — Apple Developer certificate steps
- `docs/cloudflare-setup.md` — tunnel and hostname steps
- `docs/development.md` — build, test and packaging details
- `docs/final-review.md` — what is implemented, tested and still requires you

## Known limitations

- Apple Wallet pass rendering is controlled by iOS/watchOS; the in-app preview is
  an approximation.
- Pushes are best-effort. A device that is offline fetches the newest revision
  the next time it checks.
- The app cannot extend the validity of a PureGym access code.
- `swift test` discovery is broken when only CommandLineTools is installed; use
  `swift run GymPassTests`.
