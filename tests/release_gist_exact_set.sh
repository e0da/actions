#!/bin/sh
set -eu

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

awk '
  /<<'"'"'RECONCILER'"'"'$/ { copying = 1; next }
  copying && /^          RECONCILER$/ { exit }
  copying { sub(/^          /, ""); print }
' .github/workflows/release-gist.yml >"$work/embedded-reconciler.mjs"
cmp .github/scripts/reconcile-gist-files.mjs "$work/embedded-reconciler.mjs"

cat >"$work/before.json" <<'JSON'
{
  "truncated": false,
  "files": {
    "manifest.json": {"content": "{\"files\":[{\"path\":\"manifest.json\"},{\"path\":\"keep.txt\"},{\"path\":\"remove.txt\"}]}"},
    "keep.txt": {"content": "old"},
    "remove.txt": {"content": "remove"},
    "unmanaged.txt": {"content": "preserve"}
  }
}
JSON
cat >"$work/payload.json" <<'JSON'
{
  "description": "next",
  "files": {
    "manifest.json": {"content": "{\"files\":[{\"path\":\"manifest.json\"},{\"path\":\"keep.txt\"},{\"path\":\"new.txt\"}]}"},
    "keep.txt": {"content": "new"},
    "new.txt": {"content": "new"}
  }
}
JSON

bun .github/scripts/reconcile-gist-files.mjs prepare \
  "$work/before.json" "$work/payload.json" manifest.json \
  "$work/request.json" "$work/expectation.json"

jq -e '.files | has("remove.txt") and .["remove.txt"] == null' "$work/request.json" >/dev/null
jq -e '.files | has("unmanaged.txt") | not' "$work/request.json" >/dev/null
jq -e '.expected_names == ["keep.txt", "manifest.json", "new.txt", "unmanaged.txt"]' \
  "$work/expectation.json" >/dev/null

cat >"$work/after.json" <<'JSON'
{
  "truncated": false,
  "files": {
    "manifest.json": {"content": "{\"files\":[{\"path\":\"manifest.json\"},{\"path\":\"keep.txt\"},{\"path\":\"new.txt\"}]}"},
    "keep.txt": {"content": "new"},
    "new.txt": {"content": "new"},
    "unmanaged.txt": {"content": "preserve"}
  }
}
JSON
bun .github/scripts/reconcile-gist-files.mjs verify \
  "$work/after.json" "$work/payload.json" "$work/expectation.json"

jq '.files["remove.txt"] = {"content":"stale"}' "$work/after.json" >"$work/stale.json"
if bun .github/scripts/reconcile-gist-files.mjs verify \
  "$work/stale.json" "$work/payload.json" "$work/expectation.json" 2>/dev/null
then
  echo "exact-set verification accepted a stale managed file" >&2
  exit 1
fi

jq '.truncated = true' "$work/before.json" >"$work/truncated-before.json"
if bun .github/scripts/reconcile-gist-files.mjs prepare \
  "$work/truncated-before.json" "$work/payload.json" manifest.json \
  "$work/truncated-request.json" "$work/truncated-expectation.json" 2>/dev/null
then
  echo "exact-set preparation accepted a truncated Gist listing" >&2
  exit 1
fi

jq '.truncated = true' "$work/after.json" >"$work/truncated-after.json"
if bun .github/scripts/reconcile-gist-files.mjs verify \
  "$work/truncated-after.json" "$work/payload.json" "$work/expectation.json" 2>/dev/null
then
  echo "exact-set verification accepted a truncated Gist listing" >&2
  exit 1
fi

bun .github/scripts/reconcile-gist-files.mjs prepare \
  "$work/before.json" "$work/payload.json" "" \
  "$work/subset-request.json" "$work/subset-expectation.json"
jq -S . "$work/payload.json" >"$work/payload-normalized.json"
jq -S . "$work/subset-request.json" >"$work/subset-normalized.json"
cmp "$work/payload-normalized.json" "$work/subset-normalized.json"
bun .github/scripts/reconcile-gist-files.mjs verify \
  "$work/after.json" "$work/payload.json" "$work/subset-expectation.json"

jq 'del(.files["manifest.json"])' "$work/before.json" >"$work/unmanaged-before.json"
bun .github/scripts/reconcile-gist-files.mjs prepare \
  "$work/unmanaged-before.json" "$work/payload.json" manifest.json \
  "$work/adoption-request.json" "$work/adoption-expectation.json"
jq -e '.files["remove.txt"] == null and .files["unmanaged.txt"] == null' \
  "$work/adoption-request.json" >/dev/null
jq -e '.expected_names == ["keep.txt", "manifest.json", "new.txt"]' \
  "$work/adoption-expectation.json" >/dev/null

echo "release-gist exact-set fixture ok"
