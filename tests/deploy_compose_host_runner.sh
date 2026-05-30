#!/bin/sh
set -eu

fail() {
  echo "$1" >&2
  exit 1
}

require_literal() {
  file="$1"
  literal="$2"

  grep -F "$literal" "$file" >/dev/null || fail "$file missing literal: $literal"
}

require_literal \
  ".github/workflows/deploy-compose.yml" \
  "runs-on: [self-hosted, puck, puck-macos-arm64]"

if grep -F "runs-on: [self-hosted, puck]" .github/workflows/deploy-compose.yml >/dev/null; then
  fail "deploy-compose should disambiguate host deploys with puck-macos-arm64"
fi

if grep -F "puck-linux-arm64" .github/workflows/deploy-compose.yml >/dev/null; then
  fail "deploy-compose host deploys must not target the Linux runner"
fi

require_literal ".github/actionlint.yaml" "    - puck-macos-arm64"

echo "deploy-compose host runner route ok"
