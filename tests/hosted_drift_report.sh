#!/bin/sh
set -eu

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

scanner="$tmpdir/hosted-drift-scanner.sh"
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
' .github/workflows/hosted-drift-report.yml > "$scanner"
sh -n "$scanner"

make_repo() {
  name="$1"
  repo="$tmpdir/$name"
  mkdir -p "$repo/.github/workflows"
  printf '%s\n' "$repo"
}

run_scanner() {
  repo="$1"
  mode="$2"
  output="$3"
  summary="$tmpdir/${output}.summary.md"
  mkdir -p "$tmpdir/${output}.runner"
  (
    cd "$repo"
    MODE="$mode" \
      ALLOWLIST_PATH=.github/samos-hosted-runner-allowlist.tsv \
      RUNNER_TEMP="$tmpdir/${output}.runner" \
      GITHUB_STEP_SUMMARY="$summary" \
      sh "$scanner"
  ) > "$tmpdir/${output}.out" 2>&1
}

expect_success() {
  name="$1"
  repo="$2"
  mode="$3"
  run_scanner "$repo" "$mode" "$name"
}

expect_failure() {
  name="$1"
  repo="$2"
  mode="$3"
  expected="$4"
  if run_scanner "$repo" "$mode" "$name"; then
    echo "expected failure: $name" >&2
    exit 1
  fi
  grep -F "$expected" "$tmpdir/${name}.out" >/dev/null
}

assert_summary() {
  name="$1"
  expected="$2"
  grep -F "$expected" "$tmpdir/${name}.summary.md" >/dev/null
}

repo="$(make_repo no-drift)"
cat > "$repo/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [pull_request]
jobs:
  baseline:
    runs-on: [self-hosted, puck-linux-arm64]
    steps:
      - run: true
YAML
expect_success no_drift_enforce "$repo" enforce
assert_summary no_drift_enforce "| Unapproved hosted findings | 0 |"
assert_summary no_drift_enforce "| Puck/self-hosted findings | 1 |"

repo="$(make_repo unallowlisted-hosted)"
cat > "$repo/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [pull_request]
jobs:
  hosted:
    runs-on: ubuntu-latest
    steps:
      - run: true
YAML
expect_success unallowlisted_report "$repo" report
assert_summary unallowlisted_report "| Unapproved hosted findings | 1 |"
expect_failure unallowlisted_enforce "$repo" enforce "mode=enforce failed because unapproved hosted runner findings were found"

repo="$(make_repo allowlisted-hosted)"
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
expect_success allowlisted_enforce "$repo" enforce
assert_summary allowlisted_enforce "| Approved hosted findings | 1 |"
assert_summary allowlisted_enforce "| Unapproved hosted findings | 0 |"

repo="$(make_repo invalid-allowlist)"
cat > "$repo/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [pull_request]
jobs:
  baseline:
    runs-on: [self-hosted, puck-linux-arm64]
    steps:
      - run: true
YAML
cat > "$repo/.github/samos-hosted-runner-allowlist.tsv" <<'TSV'
.github/workflows/ci.yml	baseline	ubuntu-latest	not-linear	2099-12-31	bad issue key
TSV
expect_success invalid_allowlist_report "$repo" report
assert_summary invalid_allowlist_report "| Invalid allowlist entries | 1 |"
expect_failure invalid_allowlist_enforce "$repo" enforce "mode=enforce failed because invalid allowlist entries were found"

repo="$(make_repo expired-allowlist)"
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
.github/workflows/ci.yml	publish	ubuntu-latest	E0D-1080	2000-01-01	expired hosted fallback fixture
TSV
expect_failure expired_allowlist_enforce "$repo" enforce "mode=enforce failed because invalid allowlist entries were found"

repo="$(make_repo unknown-runner)"
cat > "$repo/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [pull_request]
jobs:
  dynamic:
    runs-on: ${{ matrix.runner }}
    steps:
      - run: true
YAML
expect_success unknown_enforce "$repo" enforce
assert_summary unknown_enforce "| Unknown findings | 1 |"

repo="$(make_repo reusable-allowlisted)"
cat > "$repo/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [pull_request]
jobs:
  publish:
    uses: e0da/actions/.github/workflows/ci-baseline.yml@main
    with:
      runner: ubuntu-latest
YAML
cat > "$repo/.github/samos-hosted-runner-allowlist.tsv" <<'TSV'
.github/workflows/ci.yml	publish	ubuntu-latest	E0D-1080	2099-12-31	documented hosted reusable fixture
TSV
expect_success reusable_allowlisted_enforce "$repo" enforce
assert_summary reusable_allowlisted_enforce "| Approved hosted findings | 1 |"
assert_summary reusable_allowlisted_enforce "| Unapproved hosted findings | 0 |"

repo="$(make_repo reusable-release-elixir-default)"
cat > "$repo/.github/workflows/release.yml" <<'YAML'
name: Release
on:
  push:
    tags: ["v*"]
jobs:
  release:
    uses: e0da/actions/.github/workflows/release-elixir.yml@main
    with:
      app-name: platform
      image-name: ghcr.io/e0da/platform
YAML
expect_success reusable_release_elixir_default_report "$repo" report
assert_summary reusable_release_elixir_default_report "| Unapproved hosted findings | 1 |"
expect_failure reusable_release_elixir_default_enforce "$repo" enforce "mode=enforce failed because unapproved hosted runner findings were found"

repo="$(make_repo reusable-arc-scale-set)"
cat > "$repo/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [pull_request]
jobs:
  baseline:
    uses: e0da/actions/.github/workflows/ci-baseline.yml@main
    with:
      runner: ops-linux-arm64
YAML
expect_success reusable_arc_scale_set_enforce "$repo" enforce
assert_summary reusable_arc_scale_set_enforce "| Unapproved hosted findings | 0 |"
assert_summary reusable_arc_scale_set_enforce "| Puck/self-hosted findings | 1 |"

repo="$(make_repo direct-arc-scale-set)"
cat > "$repo/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [pull_request]
jobs:
  publish:
    runs-on: ops-linux-arm64
    steps:
      - run: true
YAML
expect_success direct_arc_scale_set_enforce "$repo" enforce
assert_summary direct_arc_scale_set_enforce "| Unapproved hosted findings | 0 |"
assert_summary direct_arc_scale_set_enforce "| Puck/self-hosted findings | 1 |"

echo "hosted drift report fixtures ok"
