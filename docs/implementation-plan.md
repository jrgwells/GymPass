# Implementation plan

This is the plan GymPass was built from. It is kept current with the shipped
code; the detailed architecture lives in `docs/architecture.md`.

## Scope (v1)

Single user, one PureGym account, one Wallet pass, one Mac. No multi-user SaaS,
companion apps, billing, analytics or remote admin.

## Module layout

```
Sources/
├── GymPassShared/     status, activity, IPC DTOs, config, diagnostics, errors
├── GymPassCore/       Security, Persistence, PureGym, Wallet, APNs, Server,
│                      Tunnel, Refresh, Process, Demo, Logging, Config
├── GymPassAgentCore/  AgentRuntime, ControlServer, AgentConfiguration, installer glue
├── GymPassAgent/      executable entry point
├── GymPassApp/        SwiftUI control panel
└── GymPassTests/      custom test runner
```

The agent owns all state and secrets; the GUI is a thin, typed control client.

## Milestones (all implemented)

1. **Foundation** — SwiftPM package with pinned dependencies, shared models,
   logging, config paths, build script, docs skeleton.
2. **Thin end-to-end Wallet path** — Keychain + CryptoBox, pass builder, SHA-1
   manifest, native CMS signing, archive verification, mock PureGym, local
   Wallet server, scripted `.app` bundling and a test identity.
3. **Durable backend** — GRDB schema/migrations, atomic publication + outbox,
   registration model with token generations, full route contract, refresh
   engine with policies and coalescing, APNs adapter, tunnel supervisor,
   recovery behaviour.
4. **Native setup and management** — background agent + loopback control API +
   LaunchAgent installer, diagnostics, onboarding, dashboard, wallet editor,
   activity timeline, settings, menu bar.
5. **Polish and release evidence** — accessibility, demo mode, security review,
   packaged release build, this documentation.

## Key decisions

- **No sandbox.** A managed `cloudflared` child and Keychain access are
  impractical sandboxed; documented as a deliberate trade-off.
- **Loopback control API instead of XPC.** Works ad-hoc without a Team ID while
  remaining token-authenticated and local-only. The state boundary is identical
  to an XPC design.
- **Encrypted archive at rest.** A `.pkpass` is signed, not encrypted, so it is
  stored with AES-GCM under a Keychain key.
- **Custom test runner.** `swift test` discovery is broken with CommandLineTools.
- **LaunchAgent fallback.** `SMAppService` preferred for signed builds; the
  `launchctl` plist path is the default for ad-hoc builds.
- **Evidence-based UI labels.** The UI distinguishes "checked", "published",
  "Apple accepted the notification" and "registration received" rather than
  claiming a device is updated.

## Verification status

See `docs/final-review.md` for the per-claim evidence matrix.
