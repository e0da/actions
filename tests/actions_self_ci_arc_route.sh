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

ci_route_count="$(
  awk 'index($0, "runs-on: actions-linux-arm64") { count++ } END { print count + 0 }' \
    .github/workflows/ci.yml
)"

ci_job_count="$(
  awk '/^jobs:$/ { jobs=1; next } jobs && /^  [a-zA-Z0-9_-]+:$/ { count++ } END { print count + 0 }' \
    .github/workflows/ci.yml
)"
[ "$ci_job_count" -ge 2 ] && [ "$ci_route_count" = "$ci_job_count" ] ||
  fail ".github/workflows/ci.yml should route every self-CI job to actions-linux-arm64"

if grep -F "runs-on: [self-hosted, puck-linux-arm64]" .github/workflows/ci.yml >/dev/null; then
  fail ".github/workflows/ci.yml still routes self-CI jobs to puck-linux-arm64"
fi

if grep -F "self-hosted, actions-linux-arm64" \
  .github/workflows/ci.yml \
  .github/workflows/actions-linux-arm64-smoke.yml >/dev/null; then
  fail "Actions ARC scale-set jobs should use runs-on: actions-linux-arm64 without self-hosted"
fi

if [ -f .github/workflows/puck-linux-arm64-smoke.yml ]; then
  fail "legacy puck-linux-arm64 smoke workflow should be renamed to actions-linux-arm64-smoke.yml"
fi

require_literal ".github/workflows/actions-linux-arm64-smoke.yml" "name: Actions Linux ARM64 ARC Smoke"
require_literal ".github/workflows/actions-linux-arm64-smoke.yml" "runs-on: actions-linux-arm64"
require_literal ".github/actionlint.yaml" "    - actions-linux-arm64"

echo "actions self-ci arc route ok"
