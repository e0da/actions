#!/bin/sh
set -eu

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

scanner="$tmpdir/wiki-bundled-hosted-drift-scanner.sh"
awk '
  /^      - name: Scan workflow runner routing$/ {
    in_step=1
    next
  }
  in_step && /^        run: \|$/ {
    in_run=1
    next
  }
  in_run {
    if ($0 ~ /^          /) {
      sub(/^          /, "")
      print
      next
    }
    if ($0 == "") {
      print
      next
    }
    exit
  }
' .github/workflows/ci-wiki-bundled.yml > "$scanner"
sh -n "$scanner"

repo="$tmpdir/allowlisted-hosted"
mkdir -p "$repo/.github/workflows"

cat > "$repo/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [pull_request]
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - run: true
YAML

cat > "$repo/.github/samos-hosted-runner-allowlist.tsv" <<'TSV'
.github/workflows/ci.yml	publish	ubuntu-latest	E0D-1080	2099-12-31	documented hosted fallback fixture
TSV

summary="$tmpdir/summary.md"
mkdir -p "$tmpdir/runner"
if ! (
  cd "$repo"
  MODE=enforce \
    ALLOWLIST_PATH=.github/samos-hosted-runner-allowlist.tsv \
    RUNNER_TEMP="$tmpdir/runner" \
    GITHUB_STEP_SUMMARY="$summary" \
    sh "$scanner"
) > "$tmpdir/out" 2>&1; then
  cat "$tmpdir/out" >&2
  exit 1
fi

grep -F "| Approved hosted findings | 1 |" "$summary" >/dev/null
grep -F "| Unapproved hosted findings | 0 |" "$summary" >/dev/null

echo "wiki bundled hosted drift fixtures ok"
