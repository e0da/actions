#!/bin/sh
set -eu

workflow=.github/workflows/release-gist.yml
ci_workflow=.github/workflows/ci.yml
reconciler=.github/scripts/reconcile-gist-files.mjs

for literal in \
  '      build-command:' \
  '      payload-path:' \
  '      managed-manifest-file:' \
  '      artifact-path:' \
  '            echo "gist-id and gist-token must be configured together" >&2' \
  '            --request PATCH' \
  "<<'RECONCILER'" \
  'reconcile-gist-files.mjs" prepare' \
  'reconcile-gist-files.mjs" verify'
do
  grep -F -- "$literal" "$workflow" >/dev/null || {
    echo "release-gist contract missing: $literal" >&2
    exit 1
  }
done

grep -F '      - uses: oven-sh/setup-bun@v2' "$ci_workflow" >/dev/null || {
  echo "Actions fixture CI must install the reconciler runtime" >&2
  exit 1
}

grep -F 'Gist read-back mismatch:' "$reconciler" >/dev/null || {
  echo "release-gist read-back verifier is missing" >&2
  exit 1
}

grep -F 'POST' "$workflow" >/dev/null && {
  echo "release-gist must never create a gist" >&2
  exit 1
}

echo "release-gist contract fixture ok"
