# Research

This documents the authoritative behaviour GymPass depends on and the
assumptions that still require live verification.

## Apple Wallet PassKit

Sources: Apple's `WalletPasses` framework documentation (pass schema, web
service endpoints) and the archived PassKit Programming Guide (layout and
conditional updates).

### Pass format

- A `.pkpass` is a ZIP archive with files at the archive root (no parent folder).
- `pass.json` — the pass definition (`formatVersion: 1` is required).
- `manifest.json` — a dictionary of `filename → SHA-1 hex` for every file in the
  archive except `manifest.json` and `signature` itself. These hashes remain
  SHA-1; this is a format requirement, not a security choice.
- `signature` — a detached PKCS#7/CMS signature over `manifest.json`, produced
  with the Pass Type ID certificate and private key. The signing digest is
  SHA-256. Wallet validates the signature against Apple's intermediate chain.
- Required images for a generic pass: `icon.png` and scale variants; `logo`,
  `thumbnail` and `strip` are optional but used here for polish.

GymPass builds the signature with Security.framework's `CMSEncoder*` API. No
OpenSSL executable or plaintext key export is required at runtime. Apple's newer
`CMSEncodeContent` path is studied; the `CMSEncoder*` API is used because it is
available in the CommandLineTools SDK and lets us embed the signer identity
directly.

### Barcode

A generic pass uses the `barcodes` array:

```json
{ "format": "PKBarcodeFormatQR", "message": "<verbatim access code>",
  "messageEncoding": "iso-8859-1" }
```

The message is the PureGym payload exactly as received. It is never rewritten to
a URL, hash or screenshot. `iso-8859-1` is used because it is byte-equivalent to
UTF-8 for the ASCII payload and is the most compatible encoding.

### Web service protocol

The pass embeds `webServiceURL` and `authenticationToken`. Wallet appends its
versioned routes (`/v1/...`) to `webServiceURL`, so the app must not append `/v1`
itself.

| Route | Authorization |
|---|---|
| `POST /v1/devices/{dli}/registrations/{pti}/{serial}` | `Authorization: ApplePass <token>` |
| `DELETE /v1/devices/{dli}/registrations/{pti}/{serial}` | same |
| `GET /v1/devices/{dli}/registrations/{pti}?passesUpdatedSince=` | device library identifier acts as the shared secret |
| `GET /v1/passes/{pti}/{serial}` | `Authorization: ApplePass <token>` |
| `POST /v1/log` | none |

The download URL contains the pass type and serial, not a device identifier, so
a successful download cannot prove which physical device fetched it. GymPass
never claims per-device delivery. Change notifications are sent to every
registered token; a device that is offline fetches the newest revision later.

### Expiry and voiding

`expirationDate` hides an expired pass; `voided` marks it permanently invalid.
GymPass never sets `voided` for a temporary outage. `expirationDate` is not set
from the advisory refresh hint.

### Apple Watch

An eligible pass added to iPhone Wallet is also available on the paired Apple
Watch; no watchOS app is required. The user double-clicks the side button,
selects the pass and presents the QR to the scanner. This is documented by
Apple; GymPass cannot detect Watch installation, so the UI reports
registrations and offers a manual "I can see the pass on my Watch" confirmation.

## PureGym API (unofficial)

Primary source: *How I accidentally became PureGym's unofficial Apple Wallet
developer* (August 2025). Treated as a research lead, not a contract.

Observed endpoints:

- `POST https://auth.puregym.com/connect/token`
  `Content-Type: application/x-www-form-urlencoded`
  `Authorization: Basic cm8uY2xpZW50Og==`
  body: `grant_type=password&username={email}&password={pin}&scope=pgcapi offline_access`
- Refresh: same endpoint with `grant_type=refresh_token`.
- `GET https://capi.puregym.com/api/v2/member/qrcode` (Bearer) returns:

```json
{
  "QrCode": "exerp:checkin:<part1>-<part2>-<part3>",
  "RefreshAt": "2025-08-14T12:08:27.4349618Z",
  "ExpiresAt": "2025-08-21T12:02:27.4349618Z",
  "RefreshIn": "0:01:00",
  "ExpiresIn": "167:55:00"
}
```

- `GET https://capi.puregym.com/api/v1/gyms/` returns gyms with string
  `latitude`/`longitude`.
- Member metadata shape is not guaranteed and is parsed leniently.

### Open questions requiring live verification

The author reports that the code refreshes every 60 seconds but technically
expires after about a week, and that a screenshot from the previous day was
rejected. Whether each issuance invalidates the previous code, and whether using
the official app invalidates GymPass's code, has **not** been established here.
This is the single most important empirical question for unattended reliability.

`RefreshEngine` therefore ships three policies and defaults to `balanced`, and
the next check is always bounded by a floor. A live probe is documented in
`docs/development.md`.

## macOS background services

- `SMAppService` is the modern API and is preferred for Team-ID-signed builds.
  It requires a signed bundle and, for agents, an embedded LaunchAgents plist.
- With only CommandLineTools available (no Developer ID), GymPass installs a
  per-user LaunchAgent plist and bootstraps it with `launchctl`. This works
  ad-hoc and is the default here.
- Per-user agents do not run before the user logs in, and cannot be relied on
  while the system is asleep. GymPass states this explicitly.

## Toolchain findings

- macOS 26.6, Swift 6.3.1, SDK 26.4.1, arm64.
- `xcodebuild` and `actool` are unavailable without Xcode, so the project avoids
  asset catalogs and assembles its `.app` with a script.
- `swift-testing` ships with CommandLineTools but SwiftPM does not add its
  framework search path, and test discovery returns zero tests. GymPass therefore
  ships a small custom runner (`swift run GymPassTests`) that exercises the same
  tests reliably.
- Security.framework `CMSEncoder*`/`CMSDecoder*` are present in the CLT SDK.

## Pinned dependencies

| Package | Version |
|---|---|
| Hummingbird | 2.27.0 |
| GRDB.swift | 7.11.1 |
| ZIPFoundation | 0.9.20 |
| swift-service-lifecycle | 2.12.0 |
| swift-crypto / swift-certificates (transitive) | resolved by Hummingbird |
