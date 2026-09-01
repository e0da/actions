#!/bin/sh
set -eu

workflow=.github/workflows/release-gist.yml

for literal in \
  '      build-command:' \
  '      payload-path:' \
  '      artifact-path:' \
  '            echo "gist-id and gist-token must be configured together" >&2' \
  '            --request PATCH' \
  'Gist read-back mismatch:'
do
  grep -F -- "$literal" "$workflow" >/dev/null || {
    echo "release-gist contract missing: $literal" >&2
    exit 1
  }
done

grep -F 'POST' "$workflow" >/dev/null && {
  echo "release-gist must never create a gist" >&2
  exit 1
}

echo "release-gist contract fixture ok"
