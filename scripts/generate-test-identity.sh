#!/bin/bash
# Generates a TEST-ONLY self-signed pass signing identity for the automated
# test suite. This certificate is not trusted by Apple and cannot produce a
# pass that installs on a real device. Never use it in production.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Tests/Fixtures"
mkdir -p "$OUT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASSWORD="gympass-test"

openssl req -x509 -newkey rsa:2048 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -nodes -sha256 \
  -subj "/CN=GymPass Test Pass/OU=TESTTEAM123/UID=pass.com.jackwells.gympass.test/O=GymPass Test/C=US" \
  >/dev/null 2>&1

openssl pkcs12 -export \
  -out "$OUT/test-identity.p12" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -password "pass:$PASSWORD" \
  >/dev/null 2>&1

echo "Wrote $OUT/test-identity.p12 (password: $PASSWORD)"
openssl x509 -in "$TMP/cert.pem" -noout -subject
