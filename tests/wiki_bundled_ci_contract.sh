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

require_input_default() {
  input_name="$1"
  expected_default="$2"

  if ! awk -v input_name="$input_name" -v expected_default="$expected_default" '
    $0 == "      " input_name ":" { in_input=1; next }
    in_input && /^      [a-zA-Z0-9_-]+:$/ { exit }
    in_input && $0 == "        default: " expected_default { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$workflow"; then
    echo "input $input_name does not keep default $expected_default" >&2
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
require_literal "      result-contract-mode:"
require_literal "        description: \"Result contract mode. Legacy and observe preserve existing Wiki step consequences; enforce makes the verification contract gate authoritative.\""
require_literal "        default: legacy"
require_literal "      verification-target:"
require_literal "        default: merge"
require_literal "      result-policy-path:"
require_literal "        default: .github/wiki-verification-policy.json"
require_input_default result-contract-mode legacy
require_input_default verification-target merge
require_input_default result-policy-path .github/wiki-verification-policy.json
require_literal "    outputs:"
require_literal "      result-contract-version:"
require_literal "        value: \${{ jobs['wiki-ci'].outputs['result-contract-version'] }}"
require_literal "      result-target:"
require_literal "        value: \${{ jobs['wiki-ci'].outputs['result-target'] }}"
require_literal "      result-conclusion:"
require_literal "        value: \${{ jobs['wiki-ci'].outputs['result-conclusion'] }}"
require_literal "  wiki-ci:"
require_literal "    name: Wiki CI"
require_literal "    runs-on: \${{ inputs.runner }}"
require_literal "    outputs:"
require_literal "      result-contract-version: \${{ steps.verification_contract.outputs['result-contract-version'] }}"
require_literal "      result-target: \${{ steps.verification_contract.outputs['result-target'] }}"
require_literal "      result-conclusion: \${{ steps.verification_contract.outputs['result-conclusion'] }}"
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
require_literal "      - name: Collect verification contract"
require_literal "        id: verification_contract"
require_literal "        if: always() && inputs['result-contract-mode'] != 'legacy'"
require_literal "        continue-on-error: true"
require_literal "          RESULT_CONTRACT_MODE: \${{ inputs['result-contract-mode'] }}"
require_literal "          VERIFICATION_TARGET: \${{ inputs['verification-target'] }}"
require_literal "          RESULT_POLICY_PATH: \${{ inputs['result-policy-path'] }}"
require_literal "          LEGACY_JOB_STATUS: \${{ job.status }}"
require_literal "          LEGACY_CONCLUSION: \${{ (steps.link_check_linux_install.outcome == 'failure' || steps.link_check_linux_install.outcome == 'cancelled' || steps.link_check_linux_preinstalled.outcome == 'failure' || steps.link_check_linux_preinstalled.outcome == 'cancelled' || steps.link_check_macos.outcome == 'failure' || steps.link_check_macos.outcome == 'cancelled') && 'fail' || 'pass' }}"
require_literal "      - name: Enforce verification contract"
require_literal "        if: always() && inputs['result-contract-mode'] == 'enforce'"
require_literal "      - name: Enforce remote link result"
require_literal "        if: always() && inputs['result-contract-mode'] != 'enforce'"
require_literal "GITHUB_STEP_SUMMARY"

step_line() {
  name="$1"
  grep -n -F "      - name: $name" "$workflow" | tail -n 1 | cut -d: -f1
}

frontmatter_line="$(step_line "Validate YAML frontmatter in .md files")"
build_line="$(step_line "Build")"
test_line="$(step_line "Test")"
summary_line="$(step_line "Write check summary")"
collector_line="$(step_line "Collect verification contract")"
contract_gate_line="$(step_line "Enforce verification contract")"
gate_line="$(step_line "Enforce remote link result")"

if ! [ "$frontmatter_line" -lt "$build_line" ] ||
   ! [ "$build_line" -lt "$test_line" ] ||
   ! [ "$test_line" -lt "$summary_line" ] ||
   ! [ "$summary_line" -lt "$collector_line" ] ||
   ! [ "$collector_line" -lt "$contract_gate_line" ] ||
   ! [ "$contract_gate_line" -lt "$gate_line" ]; then
  echo "wiki evidence and compatibility gate steps are out of order" >&2
  exit 1
fi

summary_row_count="$(awk '
  $0 == "      - name: Write check summary" { in_summary=1; next }
  in_summary && /^      - name:/ { exit }
  in_summary && /echo "\| (Approval|Hosted drift|PR title|Secret scan|Broken links|Frontmatter|Jekyll build|Repository tests) \|/ { count++ }
  END { print count + 0 }
' "$workflow")"

if [ "$summary_row_count" -ne 8 ]; then
  echo "Wiki CI summary must keep exactly eight legacy check rows" >&2
  exit 1
fi

unprotected_precollector_steps="$(awk '
  function finish_step() {
    if (in_step && !protected_step) {
      print step_label
    }
  }
  $0 == "      - name: Collect verification contract" {
    finish_step()
    in_step=0
    exit
  }
  /^      - name:/ || /^      - uses:/ {
    finish_step()
    step_label=$0
    in_step=1
    protected_step=0
    next
  }
  in_step && ($0 == "        continue-on-error: true" ||
    $0 == "        continue-on-error: ${{ inputs['\''result-contract-mode'\''] == '\''enforce'\'' }}") {
    protected_step=1
  }
  END { finish_step() }
' "$workflow")"

if [ -n "$unprotected_precollector_steps" ]; then
  echo "pre-collector steps can still fail independently in enforce mode:" >&2
  echo "$unprotected_precollector_steps" >&2
  exit 1
fi

softened_step_ids="$(awk '
  function finish_step() {
    if (in_step && softened) {
      if (step_id == "") {
        print "missing-id:" step_label
      } else {
        print step_id
      }
    }
  }
  $0 == "      - name: Collect verification contract" {
    finish_step()
    in_step=0
    exit
  }
  /^      - name:/ || /^      - uses:/ {
    finish_step()
    step_label=$0
    step_id=""
    softened=0
    in_step=1
    next
  }
  in_step && /^        id: / {
    step_id=$0
    sub(/^        id: /, "", step_id)
  }
  in_step && $0 == "        continue-on-error: ${{ inputs['\''result-contract-mode'\''] == '\''enforce'\'' }}" {
    softened=1
  }
  END { finish_step() }
' "$workflow")"

expected_softened_step_ids="$(printf '%s\n' \
  runner_tools \
  runner_contract \
  checkout \
  github_cli \
  approval_report \
  pr_title \
  hosted_drift \
  gitleaks_install \
  lychee_install_macos \
  ruby_setup_linux \
  ruby_setup_macos \
  frontmatter \
  ripgrep_install \
  build \
  wiki_test \
  check_summary)"

if [ "$softened_step_ids" != "$expected_softened_step_ids" ]; then
  echo "enforce-softened predecessor IDs do not match the legacy-blocking set" >&2
  printf 'expected:\n%s\nactual:\n%s\n' "$expected_softened_step_ids" "$softened_step_ids" >&2
  exit 1
fi

for step_id in $expected_softened_step_ids; do
  environment_name="$(printf '%s' "$step_id" | tr '[:lower:]' '[:upper:]')"
  require_literal "          LEGACY_${environment_name}_OUTCOME: \${{ steps.$step_id.outcome }}"
  require_literal "\${LEGACY_${environment_name}_OUTCOME:-}"
done

if grep -F "LEGACY_SECRET_SCAN_OUTCOME:" "$workflow" >/dev/null; then
  echo "advisory secret scan must not contribute to legacy failure parity" >&2
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
  tests/wiki_bundled_link_evidence.sh \
  tests/wiki_verification_minimal_contract.sh
do
  if ! grep -F "sh $fixture" "$self_ci" >/dev/null; then
    echo "Actions CI does not run wiki fixture: $fixture" >&2
    exit 1
  fi
done

echo "wiki bundled CI contract fixture ok"
