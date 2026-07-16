#!/bin/sh
set -eu

workflow=.github/workflows/ci-wiki-bundled.yml
self_ci=.github/workflows/ci.yml

if [ ! -f "$workflow" ]; then
  echo "missing workflow: $workflow" >&2
  exit 1
fi

require_literal() {
  expected="$1"
  if ! grep -F "$expected" "$workflow" >/dev/null; then
    echo "missing expected workflow text: $expected" >&2
    exit 1
  fi
}

require_literal "name: Reusable Wiki CI"
require_literal "  workflow_call:"
require_literal "      runner:"
require_literal "      runner-profile:"
require_literal "      runner-capabilities:"
require_literal "      runner-manifest:"
require_literal "      tool-mode:"
require_literal "      link-args:"
require_literal "      ruby-version:"
require_literal "      build-command:"
require_literal "      test-command:"
require_literal "      hosted-drift-mode:"
require_literal "      hosted-drift-allowlist-path:"
require_literal "      approval-labels:"
require_literal "      approval-report:"
require_literal "  wiki-ci:"
require_literal "    name: Wiki CI"
require_literal "    runs-on: \${{ inputs.runner }}"
require_literal "      - name: Validate runner contract"
require_literal "              gh|ruby|brew|make|lychee|bun|jq)"
require_literal "Expected one of: gh, ruby, brew, make, lychee, bun, jq."
require_literal "      - name: Approval report"
require_literal "      - name: Check PR title"
require_literal "      - name: Scan workflow runner routing"
require_literal "      - name: Secret scan"
require_literal "        continue-on-error: true"
require_literal "      - name: Check links"
require_literal "      - name: Validate YAML frontmatter in .md files"
require_literal "      - name: Build"
require_literal "      - name: Test"
require_literal "      - name: Write check summary"
require_literal "      - name: Enforce remote link result"
require_literal "GITHUB_STEP_SUMMARY"

step_line() {
  name="$1"
  grep -n -F "      - name: $name" "$workflow" | tail -n 1 | cut -d: -f1
}

frontmatter_line="$(step_line "Validate YAML frontmatter in .md files")"
build_line="$(step_line "Build")"
test_line="$(step_line "Test")"
summary_line="$(step_line "Write check summary")"
gate_line="$(step_line "Enforce remote link result")"

if ! [ "$frontmatter_line" -lt "$build_line" ] ||
   ! [ "$build_line" -lt "$test_line" ] ||
   ! [ "$test_line" -lt "$summary_line" ] ||
   ! [ "$summary_line" -lt "$gate_line" ]; then
  echo "wiki evidence and compatibility gate steps are out of order" >&2
  exit 1
fi

for step_id in \
  link_check_linux_install \
  link_check_linux_preinstalled \
  link_check_macos
do
  if ! awk -v id="$step_id" '
    $0 == "        id: " id { in_step=1; next }
    in_step && /^      - name:/ { exit }
    in_step && $0 == "        continue-on-error: true" { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$workflow"; then
    echo "remote link step does not preserve later evidence: $step_id" >&2
    exit 1
  fi
done

for fixture in \
  tests/wiki_bundled_ci_contract.sh \
  tests/wiki_bundled_hosted_drift.sh \
  tests/wiki_bundled_link_evidence.sh
do
  if ! grep -F "sh $fixture" "$self_ci" >/dev/null; then
    echo "Actions CI does not run wiki fixture: $fixture" >&2
    exit 1
  fi
done

echo "wiki bundled CI contract fixture ok"
