# Final review

## Summary

GymPass is a native macOS utility that keeps a PureGym access code current in
Apple Wallet. It is a SwiftUI control panel plus a per-user background agent that
authenticates with PureGym, generates and signs a `.pkpass`, serves Apple's
Wallet update protocol, and pushes change notifications.

- **Branch:** `feature/puregym-wallet-macos`
- **Latest commit:** `git log -1 --oneline` on this branch
- **Build:** `swift build` succeeds; `./scripts/build-app.sh` produces a signed
  `dist/GymPass.app` (ad-hoc) that launches and quits cleanly.
- **Tests:** `swift run GymPassTests` → **36 passed, 0 failed**
- **Swift source:** ~8,600 lines across 73 tracked files

## What was built

| Component | Notes |
|---|---|
| `GymPassShared` | Status, activity, IPC DTOs, configuration, diagnostics, errors |
| Security | Keychain secret store, AES-GCM `CryptoBox`, central `Redactor`, signing identity store |
| Persistence | GRDB schema + migrations, registrations with token generations, pass state, QR state, outbox, bounded activity, config |
| PureGym | `PureGymClient` actor (token auth, QR, gyms, member), rate limiting, typed errors, deterministic mock |
| Wallet | `PassBuilder`, Core Graphics asset renderer, SHA-1 manifest, in-memory zip, native CMS signer and verifier, `WalletPassService` |
| Server | `WalletHTTPServer` implementing the full Wallet protocol plus scoped installation routes |
| APNs | Certificate-authenticated HTTP/2 client with a durable outbox and generation-safe token removal |
| Tunnel | `PublicIngressProvider` abstraction and supervised `cloudflared` child process |
| Refresh | `RefreshEngine` with coalescing, three policies, bounded backoff and atomic publication |
| Agent | `AgentRuntime`, loopback token-authenticated control API, LaunchAgent installer, power assertion, diagnostics, demo mode |
| GUI | Dashboard, Wallet editor with live preview, Activity timeline, Diagnostics with redacted export, Settings, Onboarding, Menu bar extra |

## Important design decisions

- **Agent owns everything.** The GUI never touches the database or Keychain; it
  sends typed requests over a loopback, token-authenticated HTTP control API and
  receives sanitized snapshots.
- **Atomic publication.** Archive, revision, timestamps and outbox rows commit in
  one transaction; APNs is sent only after commit. Failures preserve the last
  known-good pass.
- **Encrypted at rest.** A `.pkpass` is signed, not encrypted, so the archive and
  raw access code are AES-GCM encrypted under a Keychain key.
- **Native signing.** Security.framework CMS; no OpenSSL binary or plaintext key.
- **LaunchAgent fallback.** Ad-hoc builds use `launchctl`; a Team-ID-signed build
  can switch to `SMAppService`.
- **Evidence-based UI.** The UI reports what is actually known (checked,
  published, Apple accepted, registration received) rather than inventing device
  state.

## Security decisions

- Keychain-held secrets, `0600`/`0700` file permissions, encrypted database blobs.
- Wallet server loopback-only; control API on a separate, never-tunneled port.
- Install links are separate expiring capability tokens that never expose the
  Wallet token.
- Central redaction and bounded logs body limits, and per-IP soft rate limiting.
- Not sandboxed, documented as a deliberate trade-off.

## Tests performed

`swift run GymPassTests` (36 tests) covers:

- Refresh scheduling (floor, expiry margin, bounded backoff, clamping, triggers)
- Redaction of planted secrets and sensitive URL query values
- PureGym response decoding and long durations
- Pass JSON (verbatim QR, ISO-8859-1, sharing prohibition), SHA-1 manifest, zip root layout, PNG assets
- CMS signing, full archive verification, tamper rejection and manifest mismatch
- Persistence CRUD, stale-generation guard, atomic publication, config, bounded activity
- Wallet route contract: 201/200 registration, malformed 400, lookup 200/204, download 200 with `application/vnd.apple.pkpass`, `If-Modified-Since` 304, 401 before disclosure, 404 unknown route
- Installation link expiry/revocation and install page/pass download
- Refresh engine: publish, unchanged, republish on appearance change, failure preserves the pass, auth failure, notification to registered devices

Additionally, the agent was exercised live in demo mode over the control API:
credentials → certificate import → pass publication (revision 1), and the
packaged `.app` was launched and quit successfully.

## Build status

- `swift build` — clean
- `swift run GymPassTests` — 36/36
- `./scripts/build-app.sh` — `dist/GymPass.app` assembled, ad-hoc signed and
  `codesign --verify` passed; app launched from the bundle

## Evidence labels

| Claim | Evidence |
|---|---|
| Native build + packaged app | **Verified with a real build/launch** |
| Pass build/sign/verify | **Verified with automated tests (test identity)** |
| Wallet protocol | **Verified with automated integration tests** |
| Persistence, outbox, refresh engine | **Verified with automated tests** |
| Agent control API + demo pipeline | **Verified against the live agent in demo mode** |
| PureGym live account | **Blocked** — no credentials supplied; endpoints documented, client ready |
| Real `.pkpass` installation | **Blocked by: Apple Pass Type ID certificate** |
| Apple Watch display + scan | **Blocked by: certificate**, then physical verification |
| Production APNs header policy | **Requires external verification** on a real installed pass |
| Cloudflare named tunnel | **Blocked by: domain/account**; Quick Tunnel usable for local testing |
| Screen-locked Keychain access | **Requires human verification** on an always-on Mac |

## UI review pass

A follow-up audit of the SwiftUI layer fixed:

- Activity empty state was rendered as a list row instead of centred.
- Wallet/Connectivity/General editors captured agent state once at first
  appearance; they now resync and never clobber unsaved edits.
- The hero QR could go stale after a refresh; the preview now refreshes with the
  published revision.
- The banner never dismissed, never animated and could appear for passive
  requests; it now auto-dismisses, animates (respecting Reduce Motion) and has a
  dismiss control.
- A single global busy flag made unrelated buttons spin; busy state is now
  per-action.
- Narrow windows overflowed: Membership/Services, action rows, colour pickers
  and fixed label columns are now adaptive (`ViewThatFits`, a wrapping layout
  and flexible minima). The window has a real 760×560 minimum.
- Onboarding is centred, resizable and dismissible (Close + Skip).
- Expired/missing certificates and unconfigured updates now offer actions.
- Wallet pass status is truthful ("Saved — automatic updates not configured",
  "Access code may have expired") and location input is validated.
- Settings reflects the agent's real preferences and refresh policy; the
  background-service toggle reflects approval state; certificate and credential
  errors show inline in their sheets.
- Dead code removed; icon-only buttons labelled; `⌘1`–`⌘4` shortcuts added.

Verified with packaged-app window captures at 760 and 1180 points.

## Known limitations

- Apple Wallet rendering is controlled by iOS/watchOS; the in-app preview is an
  approximation.
- The PureGym QR invalidation contract is unverified; refresh defaults to a
  conservative `balanced` policy and must be tuned against observations.
- `swift test` discovery is broken with CommandLineTools only; use
  `swift run GymPassTests`.
- Real pass installation and Watch use cannot be verified without a certificate
  and physical devices.

## Remaining external configuration

1. **Apple Developer** — create a Pass Type ID certificate, export a `.p12`,
   import it in Settings → Wallet (`docs/wallet-setup.md`).
2. **Cloudflare** — create a named tunnel, route a hostname, paste the token in
   Settings → Connectivity (`docs/cloudflare-setup.md`).
3. **PureGym** — enter email and PIN in the setup wizard (or Settings → PureGym).
4. **Install the pass** — scan the installation code with iPhone; optionally
   confirm it on Apple Watch.

## How to launch

```bash
./scripts/build-app.sh
open dist/GymPass.app
```

## How to enable the background agent

In the app, click **Install Background Service** when prompted, or use
**Settings → General → Run GymPass in the background**. If macOS asks for
approval, use **Settings → Advanced → Open Login Items Settings**. The agent
continues to run when the window is closed and when the GUI quits.

## How to install the Wallet pass

Signing certificate and hostname configured → open the Dashboard → **Add to
Apple Wallet** → scan the **installation code** (distinct from your gym entry
code) with your iPhone. On Apple Watch: double-click the side button, select the
pass, and present the QR to the scanner.

## Requires human verification

- Live PureGym authentication and the QR invalidation behaviour.
- A real pass installing on iPhone and appearing on the paired Apple Watch.
- Scanning the Watch at the gym.
- The production APNs header policy against a real pass.
- Keychain access while the screen is locked on an always-on Mac.
- Named-tunnel routing and that only `/v1/*` and `/install/*` are reachable.

## Outstanding blockers

None in the code. The remaining gates are external: an Apple Pass Type ID
certificate and a Cloudflare domain/account. All surrounding features are
implemented, mock-tested and present with clear UI states explaining what still
needs configuring.
