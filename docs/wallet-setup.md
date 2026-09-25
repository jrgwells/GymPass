# Apple Wallet setup

GymPass needs a **Pass Type ID certificate** and its private key to sign passes
and to authenticate Wallet push notifications. This requires a paid Apple
Developer Program membership.

> This step is human-owned and cannot be automated. Without it GymPass can build
> and verify passes with the test identity in `Tests/Fixtures`, but no pass will
> install on a real iPhone or Apple Watch.

## Steps

1. Sign in to <https://developer.apple.com/account> → **Certificates, Identifiers
   & Profiles**.
2. **Identifiers → Pass Type IDs → +**. Use a reverse-DNS name such as
   `pass.com.yourname.gympass`. Register it.
3. **Certificates → + → Pass Type ID Certificate**. Select the Pass Type ID,
   generate a CSR with Keychain Access (**Certificate Assistant → Request a
   Certificate From a Certificate Authority**), upload it, and download the
   `.cer`.
4. In Keychain Access, import the `.cer` into the **login** keychain. It pairs
   with the private key created for the CSR under **My Certificates**.
5. Export the identity as `.p12`: select the certificate and its private key →
   **File → Export Items… → Personal Information Exchange (.p12)**. Set a
   password.
6. In GymPass **Settings → Wallet → Manage Certificate…**, choose the `.p12`
   and enter its password.

GymPass derives the Pass Type ID and Team ID from the certificate, stores the
identity in your Keychain, and runs a signing self-test.

## Verify

- **Diagnostics → Test Signing** should report *Signed and verified*.
- The certificate status should read *Valid*, with an expiry date. Renew before
  it expires; renewal keeps the same Pass Type ID and serial, so installed
  passes continue to update.

## Apple Push for Wallet updates

Wallet pass updates use the **same Pass Type ID certificate** over HTTP/2 to
`api.push.apple.com`. GymPass uses certificate authentication and a `{}` body
with the pass type as the topic. No separate `.p8` key is required.

> The exact `apns-push-type`/priority combination for Wallet pushes must be
> confirmed against a real installed pass; this is isolated in
> `WalletAPNsPolicy` so it can be adjusted in one place. APNs accepting a
> notification means Apple accepted the request, not that a device applied it.
