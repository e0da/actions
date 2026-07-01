#!/bin/sh
set -eu

fail() {
  echo "$1" >&2
  exit 1
}

require_literal() {
  file="$1"
  literal="$2"

  grep -F -- "$literal" "$file" >/dev/null || fail "$file missing literal: $literal"
}

reject_literal() {
  file="$1"
  literal="$2"

  if grep -F -- "$literal" "$file" >/dev/null; then
    fail "$file should not contain literal: $literal"
  fi
}

workflow=".github/workflows/deploy-k3s.yml"
[ -f "$workflow" ] || fail "$workflow is required"

require_literal "$workflow" "      GHCR_TOKEN:"
require_literal "$workflow" "          GH_TOKEN: \${{ secrets.GHCR_TOKEN || github.token }}"
require_literal "$workflow" "          GH_USER: \${{ github.actor }}"
require_literal "$workflow" "auth_b64=\"\$(printf '%s:%s' \"\${GH_USER}\" \"\${GH_TOKEN}\" | base64 | tr -d '\\n')\""
require_literal "$workflow" "-H \"Authorization: Basic \${auth_b64}\""
require_literal "$workflow" "GHCR digest check could not authenticate (HTTP \${status})"
require_literal "$workflow" "Configure GHCR_TOKEN with read:packages"
require_literal "$workflow" "image digest not found in GHCR (HTTP \${status})"

reject_literal "$workflow" 'Authorization: Bearer'
reject_literal "$workflow" "printf '%s' \"\${GH_TOKEN}\" | base64"

echo "deploy-k3s GHCR auth contract ok"
