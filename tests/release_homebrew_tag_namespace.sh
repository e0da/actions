#!/bin/sh
set -eu

fail() {
  echo "$1" >&2
  exit 1
}

workflow=".github/workflows/release-homebrew-interface.yml"
[ -f "$workflow" ] || fail "$workflow is required"

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
resolver="$fixture_dir/resolve-release-tag.sh"

awk '
  /# release-tag-namespace-script:start/ { capture = 1; next }
  /# release-tag-namespace-script:end/ { capture = 0 }
  capture {
    sub(/^          /, "")
    print
  }
' "$workflow" > "$resolver"
[ -s "$resolver" ] || fail "release tag namespace resolver is missing"
sh -n "$resolver"

resolve_tag() {
  prefix="$1"
  source_tag="$2"
  output="$fixture_dir/output"
  : > "$output"
  RELEASE_TAG_PREFIX="$prefix" GITHUB_REF_NAME="$source_tag" GITHUB_OUTPUT="$output" sh "$resolver" || return $?
  sed -n 's/^destination-tag=//p' "$output"
}

[ "$(resolve_tag "" "v1.2.3")" = "v1.2.3" ] ||
  fail "empty prefix must preserve the source tag"
[ "$(resolve_tag "world-modeler-" "v1.2.3")" = "world-modeler-v1.2.3" ] ||
  fail "product prefix must namespace the destination tag"
[ "$(resolve_tag "alx-" "v1.2.3")" != "$(resolve_tag "world-modeler-" "v1.2.3")" ] ||
  fail "distinct product prefixes must not collide for the same source tag"
[ "$(resolve_tag "world-modeler-" "v1.2.3-rc.1")" = "world-modeler-v1.2.3-rc.1" ] ||
  fail "product prefix must preserve prerelease source tags"

for invalid_prefix in \
  "World-Modeler-" \
  "world_modeler-" \
  "world/modeler-" \
  'world;modeler-' \
  "-world-modeler-" \
  "world--modeler-" \
  "world-modeler" \
  "world modeler-"
do
  if resolve_tag "$invalid_prefix" "v1.2.3" > /dev/null 2>&1; then
    fail "invalid release tag prefix was accepted: $invalid_prefix"
  fi
done

invalid_multiline=$(printf 'valid\nhax-')
if resolve_tag "$invalid_multiline" "v1.2.3" > /dev/null 2>&1; then
  fail "multiline release tag prefix was accepted"
fi
invalid_carriage_return=$(printf 'valid\rhax-')
if resolve_tag "$invalid_carriage_return" "v1.2.3" > /dev/null 2>&1; then
  fail "carriage-return release tag prefix was accepted"
fi

grep -F 'release-tag-prefix:' "$workflow" >/dev/null ||
  fail "release-tag-prefix input is missing"
grep -F 'default: ""' "$workflow" >/dev/null ||
  fail "release-tag-prefix must default to empty"
grep -F "gh release view \"\$DESTINATION_TAG\"" "$workflow" >/dev/null ||
  fail "release view must use the destination tag"
grep -F "gh release download \"\$DESTINATION_TAG\"" "$workflow" >/dev/null ||
  fail "release idempotence check must use the destination tag"
grep -F "gh release create \"\$DESTINATION_TAG\"" "$workflow" >/dev/null ||
  fail "release creation must use the destination tag"
grep -F "releases/download/\$DESTINATION_TAG/\$archive" "$workflow" >/dev/null ||
  fail "formula URL must use the destination tag"
grep -F "version=\"\${GITHUB_REF_NAME#v}\"" "$workflow" >/dev/null ||
  fail "formula version must remain source-tag-derived"
grep -F "archive=\"\${ARTIFACT_NAME}-\${safe_ref}-\${HOMEBREW_FORMULA}.tar.gz\"" "$workflow" >/dev/null ||
  fail "artifact name must remain source-tag-derived"

echo "release homebrew tag namespace contract ok"
