#!/bin/sh
set -eu

workflow=.github/workflows/ci-wiki-bundled.yml
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

extract_run_step() {
  step_name="$1"
  destination="$2"

  awk -v step_name="$step_name" '
    $0 == "      - name: " step_name { in_step=1; next }
    in_step && $0 == "        run: |" { in_run=1; next }
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
  ' "$workflow" > "$destination"

  if [ ! -s "$destination" ]; then
    echo "could not extract workflow step: $step_name" >&2
    exit 1
  fi

  sh -n "$destination"
}

summary_script="$tmpdir/write-summary.sh"
gate_script="$tmpdir/enforce-remote-links.sh"
extract_run_step "Write check summary" "$summary_script"
extract_run_step "Enforce remote link result" "$gate_script"

summary="$tmpdir/summary.md"
run_evidence_fixture() {
  remote_outcome=success

  if ! sh -c 'exit 23'; then
    remote_outcome=failure
  fi

  printf 'frontmatter evidence\n' > "$tmpdir/frontmatter"
  printf 'build evidence\n' > "$tmpdir/build"
  printf 'IA evidence\n' > "$tmpdir/ia"

  APPROVAL_OUTCOME=success \
    APPROVAL_SIGNAL=present \
    PR_TITLE_OUTCOME=success \
    HOSTED_DRIFT_OUTCOME=success \
    SECRET_SCAN_OUTCOME=success \
    SECRET_SCAN_CONCLUSION=success \
    LINK_LINUX_INSTALL_OUTCOME="$remote_outcome" \
    LINK_LINUX_PREINSTALLED_OUTCOME=skipped \
    LINK_MACOS_OUTCOME=skipped \
    FRONTMATTER_OUTCOME=success \
    BUILD_OUTCOME=success \
    TEST_OUTCOME=success \
    GITHUB_STEP_SUMMARY="$summary" \
    sh "$summary_script"

  [ -s "$tmpdir/frontmatter" ]
  [ -s "$tmpdir/build" ]
  [ -s "$tmpdir/ia" ]
  grep -F "| Broken links | fail (blocking) |" "$summary" >/dev/null
  grep -F "| Frontmatter | pass |" "$summary" >/dev/null
  grep -F "| Jekyll build | pass |" "$summary" >/dev/null
  grep -F "| Repository tests | pass |" "$summary" >/dev/null
  if grep -F "| IA test |" "$summary" >/dev/null; then
    echo "summary still uses the repository-specific IA test label" >&2
    exit 1
  fi

  : > "$summary"
  TEST_OUTCOME=failure \
    GITHUB_STEP_SUMMARY="$summary" \
    sh "$summary_script"
  grep -F "| Repository tests | fail |" "$summary" >/dev/null

  if LINK_LINUX_INSTALL_OUTCOME="$remote_outcome" \
    LINK_LINUX_PREINSTALLED_OUTCOME=skipped \
    LINK_MACOS_OUTCOME=skipped \
    sh "$gate_script" > "$tmpdir/gate.out" 2>&1; then
    echo "legacy remote-link failure unexpectedly passed" >&2
    exit 1
  fi

  grep -F "Remote link verification failed" "$tmpdir/gate.out" >/dev/null
}

run_evidence_fixture

LINK_LINUX_INSTALL_OUTCOME=success \
  LINK_LINUX_PREINSTALLED_OUTCOME=skipped \
  LINK_MACOS_OUTCOME=skipped \
  sh "$gate_script"

echo "wiki bundled link evidence fixtures ok"
