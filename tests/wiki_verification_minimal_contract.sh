#!/bin/sh
set -eu

workflow=.github/workflows/ci-wiki-bundled.yml
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

fail() {
  echo "wiki verification minimal contract: $*" >&2
  exit 1
}

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
  ' "$workflow" >"$destination"

  [ -s "$destination" ] || fail "could not extract workflow step: $step_name"
  sh -n "$destination"
}

collector="$tmpdir/collect.sh"
extract_run_step "Collect verification contract" "$collector"
enforce_gate="$tmpdir/enforce.sh"
extract_run_step "Enforce verification contract" "$enforce_gate"

if awk '
  /^[[:space:]]+(attribution|reader_impact):[[:space:]]*$/ { conditional_field=1; next }
  conditional_field && /^[[:space:]]+if / { found=1 }
  conditional_field { conditional_field=0 }
  END { exit(found ? 0 : 1) }
' "$collector"; then
  fail "collector uses conditional object values rejected by jq 1.7.1"
fi

commit=1111111111111111111111111111111111111111
tree=2222222222222222222222222222222222222222

write_policy() {
  cat >"$tmpdir/policy.json" <<'JSON'
{
  "contract_version": "wiki-verification-policy.v1",
  "policy_id": "wiki.verification-policy",
  "policy_version": "1.0.0",
  "target": "merge",
  "expected_checks": [
    {
      "check_id": "source.frontmatter",
      "applicability": "required",
      "on_violation": "block",
      "on_partial": "block",
      "on_unavailable": "block",
      "owner": "wiki-author",
      "action": "fix frontmatter and rerun"
    },
    {
      "check_id": "review.approval",
      "applicability": "optional",
      "on_violation": "advisory",
      "on_partial": "advisory",
      "on_unavailable": "advisory",
      "owner": "wiki-maintainers",
      "action": "review approval evidence"
    }
  ]
}
JSON
}

write_observation() {
  destination="$1"
  check_id="$2"
  observed_state="$3"
  availability="$4"

  jq -n \
    --arg check_id "$check_id" \
    --arg commit "$commit" \
    --arg tree "$tree" \
    --arg observed_state "$observed_state" \
    --arg availability "$availability" '
    {
      observation_version: "wiki-verification-observation.v1",
      check_id: $check_id,
      tested_commit: $commit,
      tested_tree: $tree,
      comparison_commit: null,
      comparison_tree: null,
      observed_state: $observed_state,
      availability: $availability,
      attribution: "not_applicable",
      reader_impact: [],
      evidence_ref: ("step:" + $check_id)
    }
  ' >"$destination"
}

run_collector() {
  case_name="$1"
  records_dir="$2"
  legacy_job_status="${3:-success}"
  contract_mode="${4:-observe}"
  legacy_build_outcome="${5:-success}"
  legacy_test_outcome="${6:-success}"
  legacy_secret_scan_outcome="${7:-success}"
  output="$tmpdir/$case_name.jsonl"
  summary="$tmpdir/$case_name.md"
  github_output="$tmpdir/$case_name.out"

  RESULT_CONTRACT_MODE="$contract_mode" \
    VERIFICATION_TARGET=merge \
    RESULT_POLICY_PATH="$tmpdir/policy.json" \
    RESULT_RECORDS_DIR="$records_dir" \
    RESULT_OUTPUT_PATH="$output" \
    TESTED_COMMIT="$commit" \
    TESTED_TREE="$tree" \
    LEGACY_CONCLUSION=pass \
    LEGACY_JOB_STATUS="$legacy_job_status" \
    LEGACY_BUILD_OUTCOME="$legacy_build_outcome" \
    LEGACY_WIKI_TEST_OUTCOME="$legacy_test_outcome" \
    LEGACY_SECRET_SCAN_OUTCOME="$legacy_secret_scan_outcome" \
    GITHUB_STEP_SUMMARY="$summary" \
    GITHUB_OUTPUT="$github_output" \
    sh "$collector"

  printf '%s\n' "$output|$summary|$github_output"
}

write_policy

pass_records="$tmpdir/pass-records"
mkdir -p "$pass_records"
write_observation "$pass_records/approval.json" review.approval satisfied available
write_observation "$pass_records/frontmatter.json" source.frontmatter satisfied available
jq '
  .attribution = "direct|owner\nline" |
  .reader_impact = ["reader | impact", "<script>"]
' "$pass_records/frontmatter.json" >"$tmpdir/frontmatter-summary.json"
mv "$tmpdir/frontmatter-summary.json" "$pass_records/frontmatter.json"
pass_paths="$(run_collector pass "$pass_records")"
pass_output="${pass_paths%%|*}"
pass_rest="${pass_paths#*|}"
pass_summary="${pass_rest%%|*}"
pass_github_output="${pass_rest#*|}"

[ "$(wc -l <"$pass_output" | tr -d ' ')" -eq 2 ] || fail "pass case did not emit two records"
jq -s -e '
  all(.[]; .contract_version == "wiki-verification-minimal.v1") and
  all(.[]; .applied_effect == "none") and
  [.[].check_id] == ["source.frontmatter", "review.approval"]
' "$pass_output" >/dev/null || fail "pass records are invalid"
grep -F "result-contract-version=wiki-verification-minimal.v1" "$pass_github_output" >/dev/null
grep -F "result-target=merge" "$pass_github_output" >/dev/null
grep -F "result-conclusion=trusted" "$pass_github_output" >/dev/null
grep -F "legacy-conclusion=pass" "$pass_github_output" >/dev/null
grep -F "parity=match" "$pass_github_output" >/dev/null
grep -F "## Verification Contract v1" "$pass_summary" >/dev/null
grep -F "Existing Wiki steps keep their current consequences." "$pass_summary" >/dev/null
if grep -F "The verification contract gate controls the final consequence" "$pass_summary" >/dev/null; then
  fail "observe summary claimed enforce consequence ownership"
fi
grep -F "## Verification Details" "$pass_summary" >/dev/null
grep -F "| Check ID | Observed state | Availability | Attribution | Reader impact | Applied effect | Owner | Action | Evidence |" "$pass_summary" >/dev/null
grep -F "direct&#124;owner line" "$pass_summary" >/dev/null
grep -F "reader &#124; impact, &lt;script&gt;" "$pass_summary" >/dev/null
grep -F "| wiki-author | fix frontmatter and rerun | step:source.frontmatter |" "$pass_summary" >/dev/null
source_detail_line="$(grep -n -F "| source.frontmatter |" "$pass_summary" | cut -d: -f1)"
approval_detail_line="$(grep -n -F "| review.approval |" "$pass_summary" | cut -d: -f1)"
[ "$source_detail_line" -lt "$approval_detail_line" ] || fail "summary details do not follow policy order"

enforce_paths="$(run_collector enforce "$pass_records" success enforce)"
enforce_summary="$(printf '%s' "$enforce_paths" | cut -d'|' -f2)"
grep -F "The verification contract gate controls the final consequence; legacy Wiki step outcomes are collected." \
  "$enforce_summary" >/dev/null
if grep -F "Existing Wiki steps keep their current consequences." "$enforce_summary" >/dev/null; then
  fail "enforce summary claimed legacy consequences were unchanged"
fi

softened_build_paths="$(run_collector softened-build "$pass_records" success enforce failure)"
softened_build_github_output="${softened_build_paths##*|}"
grep -F "result-conclusion=trusted" "$softened_build_github_output" >/dev/null
grep -F "legacy-conclusion=fail" "$softened_build_github_output" >/dev/null
grep -F "parity=difference" "$softened_build_github_output" >/dev/null

softened_cancelled_paths="$(run_collector softened-cancelled "$pass_records" success enforce cancelled)"
softened_cancelled_github_output="${softened_cancelled_paths##*|}"
grep -F "result-conclusion=trusted" "$softened_cancelled_github_output" >/dev/null
grep -F "legacy-conclusion=fail" "$softened_cancelled_github_output" >/dev/null
grep -F "parity=difference" "$softened_cancelled_github_output" >/dev/null

softened_test_paths="$(run_collector softened-test "$pass_records" success enforce success failure)"
softened_test_github_output="${softened_test_paths##*|}"
grep -F "result-conclusion=trusted" "$softened_test_github_output" >/dev/null
grep -F "legacy-conclusion=fail" "$softened_test_github_output" >/dev/null
grep -F "parity=difference" "$softened_test_github_output" >/dev/null

advisory_secret_scan_paths="$(run_collector advisory-secret-scan "$pass_records" success enforce success success failure)"
advisory_secret_scan_github_output="${advisory_secret_scan_paths##*|}"
grep -F "result-conclusion=trusted" "$advisory_secret_scan_github_output" >/dev/null
grep -F "legacy-conclusion=pass" "$advisory_secret_scan_github_output" >/dev/null
grep -F "parity=match" "$advisory_secret_scan_github_output" >/dev/null

legacy_failure_paths="$(run_collector legacy-failure "$pass_records" failure)"
legacy_failure_github_output="${legacy_failure_paths##*|}"
grep -F "result-conclusion=trusted" "$legacy_failure_github_output" >/dev/null
grep -F "legacy-conclusion=fail" "$legacy_failure_github_output" >/dev/null
grep -F "parity=difference" "$legacy_failure_github_output" >/dev/null

mixed_comparison_records="$tmpdir/mixed-comparison-records"
mkdir -p "$mixed_comparison_records"
write_observation "$mixed_comparison_records/approval.json" review.approval satisfied available
write_observation "$mixed_comparison_records/frontmatter.json" source.frontmatter satisfied available
jq '
  .comparison_commit = "4444444444444444444444444444444444444444" |
  .comparison_tree = "5555555555555555555555555555555555555555"
' "$mixed_comparison_records/frontmatter.json" >"$tmpdir/mixed-comparison.json"
mv "$tmpdir/mixed-comparison.json" "$mixed_comparison_records/frontmatter.json"
mixed_comparison_paths="$(run_collector mixed-comparison "$mixed_comparison_records")"
mixed_comparison_output="${mixed_comparison_paths%%|*}"
mixed_comparison_github_output="${mixed_comparison_paths##*|}"
jq -s -e '
  length == 2 and
  any(.[]; .comparison_commit == null and .comparison_tree == null) and
  any(.[];
    .comparison_commit == "4444444444444444444444444444444444444444" and
    .comparison_tree == "5555555555555555555555555555555555555555"
  )
' "$mixed_comparison_output" >/dev/null || fail "mixed comparative and non-comparative observations were rejected"
grep -F "result-conclusion=trusted" "$mixed_comparison_github_output" >/dev/null

blocking_records="$tmpdir/blocking-records"
mkdir -p "$blocking_records"
write_observation "$blocking_records/approval.json" review.approval satisfied available
write_observation "$blocking_records/frontmatter.json" source.frontmatter violated available
blocking_paths="$(run_collector blocking "$blocking_records")"
blocking_output="${blocking_paths%%|*}"
blocking_github_output="${blocking_paths##*|}"
jq -s -e '
  any(.[];
    .check_id == "source.frontmatter" and
    .observed_state == "violated" and
    .availability == "available" and
    .applied_effect == "block"
  )
' "$blocking_output" >/dev/null || fail "blocking policy was not applied"
grep -F "result-conclusion=blocked" "$blocking_github_output" >/dev/null
grep -F "parity=difference" "$blocking_github_output" >/dev/null

advisory_records="$tmpdir/advisory-records"
mkdir -p "$advisory_records"
write_observation "$advisory_records/approval.json" review.approval violated available
write_observation "$advisory_records/frontmatter.json" source.frontmatter satisfied available
advisory_paths="$(run_collector advisory "$advisory_records")"
advisory_github_output="${advisory_paths##*|}"
grep -F "result-conclusion=trusted_with_advisories" "$advisory_github_output" >/dev/null
grep -F "parity=match" "$advisory_github_output" >/dev/null

partial_records="$tmpdir/partial-records"
mkdir -p "$partial_records"
write_observation "$partial_records/approval.json" review.approval satisfied available
write_observation "$partial_records/frontmatter.json" source.frontmatter violated partial
partial_paths="$(run_collector partial "$partial_records")"
partial_output="${partial_paths%%|*}"
partial_github_output="${partial_paths##*|}"
jq -s -e '
  any(.[];
    .check_id == "source.frontmatter" and
    .observed_state == "violated" and
    .availability == "partial" and
    .applied_effect == "block"
  )
' "$partial_output" >/dev/null || fail "partial violation did not use the strongest policy effect"
grep -F "result-conclusion=blocked" "$partial_github_output" >/dev/null
grep -F 'unavailable-checks=["source.frontmatter"]' "$partial_github_output" >/dev/null

missing_records="$tmpdir/missing-records"
mkdir -p "$missing_records"
write_observation "$missing_records/approval.json" review.approval satisfied available
missing_paths="$(run_collector missing "$missing_records")"
missing_output="${missing_paths%%|*}"
missing_github_output="${missing_paths##*|}"
jq -s -e '
  any(.[];
    .check_id == "source.frontmatter" and
    .observed_state == "not_evaluated" and
    .availability == "unavailable" and
    .applied_effect == "block" and
    .owner == "actions-maintainers" and
    .action == "produce the missing verification observation and rerun" and
    .evidence_ref == "actions:missing-result"
  )
' "$missing_output" >/dev/null || fail "missing result was not synthesized"
grep -F "result-conclusion=evidence_unavailable" "$missing_github_output" >/dev/null

missing_legacy_failure_paths="$(run_collector missing-legacy-failure "$missing_records" failure)"
missing_legacy_failure_github_output="${missing_legacy_failure_paths##*|}"
grep -F "result-conclusion=evidence_unavailable" "$missing_legacy_failure_github_output" >/dev/null
grep -F "legacy-conclusion=fail" "$missing_legacy_failure_github_output" >/dev/null
grep -F "parity=match" "$missing_legacy_failure_github_output" >/dev/null

jq '
  .expected_checks |= map(
    if .check_id == "source.frontmatter" then
      .on_unavailable = "none" |
      .owner = "wiki-author" |
      .action = "caller policy must not own missing evidence"
    else . end
  )
' "$tmpdir/policy.json" >"$tmpdir/nonblocking-policy.json"
mv "$tmpdir/nonblocking-policy.json" "$tmpdir/policy.json"
nonblocking_missing_paths="$(run_collector nonblocking-missing "$missing_records")"
nonblocking_missing_output="${nonblocking_missing_paths%%|*}"
nonblocking_missing_github_output="${nonblocking_missing_paths##*|}"
jq -s -e '
  any(.[];
    .check_id == "source.frontmatter" and
    .applied_effect == "block" and
    .owner == "actions-maintainers" and
    .action == "produce the missing verification observation and rerun" and
    .evidence_ref == "actions:missing-result"
  )
' "$nonblocking_missing_output" >/dev/null || fail "caller policy controlled missing-result ownership or effect"
grep -F "result-conclusion=evidence_unavailable" "$nonblocking_missing_github_output" >/dev/null
write_policy

prerequisite_records="$tmpdir/prerequisite-records"
mkdir -p "$prerequisite_records"
write_observation "$prerequisite_records/approval.json" review.approval satisfied available
write_observation "$prerequisite_records/frontmatter.json" source.frontmatter not_evaluated unavailable
prerequisite_paths="$(run_collector prerequisite "$prerequisite_records")"
prerequisite_output="${prerequisite_paths%%|*}"
prerequisite_github_output="${prerequisite_paths##*|}"
jq -s -e '
  any(.[];
    .check_id == "source.frontmatter" and
    .observed_state == "not_evaluated" and
    .availability == "unavailable" and
    .applied_effect == "block" and
    .owner == "wiki-author" and
    .evidence_ref == "step:source.frontmatter"
  )
' "$prerequisite_output" >/dev/null || fail "prerequisite failure lost its unavailable evidence"
grep -F "result-conclusion=evidence_unavailable" "$prerequisite_github_output" >/dev/null

invalid_combo_records="$tmpdir/invalid-combo-records"
mkdir -p "$invalid_combo_records"
write_observation "$invalid_combo_records/approval.json" review.approval satisfied available
write_observation "$invalid_combo_records/frontmatter.json" source.frontmatter not_evaluated available
invalid_combo_paths="$(run_collector invalid-combo "$invalid_combo_records")"
invalid_combo_output="${invalid_combo_paths%%|*}"
invalid_combo_github_output="${invalid_combo_paths##*|}"
jq -s -e '
  length == 1 and
  .[0].check_id == "actions.contract" and
  .[0].observed_state == "not_evaluated" and
  .[0].availability == "unavailable" and
  .[0].applied_effect == "block" and
  .[0].owner == "actions-maintainers" and
  .[0].evidence_ref == "actions:invalid-observation-set"
' "$invalid_combo_output" >/dev/null || fail "invalid combination was not converted to Actions-owned unavailable evidence"
grep -F "result-conclusion=evidence_unavailable" "$invalid_combo_github_output" >/dev/null

duplicate_records="$tmpdir/duplicate-records"
mkdir -p "$duplicate_records"
write_observation "$duplicate_records/approval-a.json" review.approval satisfied available
write_observation "$duplicate_records/approval-b.json" review.approval satisfied available
write_observation "$duplicate_records/frontmatter.json" source.frontmatter satisfied available
duplicate_paths="$(run_collector duplicate "$duplicate_records")"
duplicate_output="${duplicate_paths%%|*}"
duplicate_github_output="${duplicate_paths##*|}"
jq -s -e 'length == 1 and .[0].check_id == "actions.contract" and .[0].availability == "unavailable"' \
  "$duplicate_output" >/dev/null || fail "duplicate observation was not rejected as Actions-owned unavailable evidence"
grep -F "result-conclusion=evidence_unavailable" "$duplicate_github_output" >/dev/null

unknown_records="$tmpdir/unknown-records"
mkdir -p "$unknown_records"
write_observation "$unknown_records/approval.json" review.approval satisfied available
write_observation "$unknown_records/frontmatter.json" source.frontmatter satisfied available
write_observation "$unknown_records/unknown.json" unknown.check satisfied available
unknown_paths="$(run_collector unknown "$unknown_records")"
unknown_output="${unknown_paths%%|*}"
jq -s -e 'length == 1 and .[0].check_id == "actions.contract" and .[0].owner == "actions-maintainers"' \
  "$unknown_output" >/dev/null || fail "unknown observation was not rejected as Actions-owned unavailable evidence"

identity_records="$tmpdir/identity-records"
mkdir -p "$identity_records"
write_observation "$identity_records/approval.json" review.approval satisfied available
write_observation "$identity_records/frontmatter.json" source.frontmatter satisfied available
jq '.tested_tree = "3333333333333333333333333333333333333333"' \
  "$identity_records/frontmatter.json" >"$tmpdir/wrong-identity.json"
mv "$tmpdir/wrong-identity.json" "$identity_records/frontmatter.json"
identity_paths="$(run_collector identity "$identity_records")"
identity_output="${identity_paths%%|*}"
jq -s -e 'length == 1 and .[0].check_id == "actions.contract" and .[0].evidence_ref == "actions:invalid-observation-set"' \
  "$identity_output" >/dev/null || fail "identity mismatch was not rejected before aggregation"

cross_revision_records="$tmpdir/cross-revision-records"
mkdir -p "$cross_revision_records"
write_observation "$cross_revision_records/approval.json" review.approval satisfied available
write_observation "$cross_revision_records/frontmatter.json" source.frontmatter satisfied available
jq '
  .comparison_commit = "4444444444444444444444444444444444444444" |
  .comparison_tree = "5555555555555555555555555555555555555555"
' "$cross_revision_records/approval.json" >"$tmpdir/approval-comparison.json"
mv "$tmpdir/approval-comparison.json" "$cross_revision_records/approval.json"
jq '
  .comparison_commit = "6666666666666666666666666666666666666666" |
  .comparison_tree = "7777777777777777777777777777777777777777"
' "$cross_revision_records/frontmatter.json" >"$tmpdir/frontmatter-comparison.json"
mv "$tmpdir/frontmatter-comparison.json" "$cross_revision_records/frontmatter.json"
cross_revision_paths="$(run_collector cross-revision "$cross_revision_records")"
cross_revision_output="${cross_revision_paths%%|*}"
jq -s -e 'length == 1 and .[0].check_id == "actions.contract" and .[0].availability == "unavailable"' \
  "$cross_revision_output" >/dev/null || fail "cross-revision observations were aggregated"

assert_preflight_report() {
  case_name="$1"
  contract_mode="$2"
  target="$3"
  tested_commit="$4"
  tested_tree="$5"
  legacy_job_status="${6:-success}"
  expected_parity="${7:-difference}"
  preflight_output="$tmpdir/preflight-$case_name.jsonl"
  preflight_summary="$tmpdir/preflight-$case_name.md"
  preflight_github_output="$tmpdir/preflight-$case_name.out"

  if ! RESULT_CONTRACT_MODE="$contract_mode" \
    VERIFICATION_TARGET="$target" \
    RESULT_POLICY_PATH="$tmpdir/policy.json" \
    RESULT_RECORDS_DIR="$pass_records" \
    RESULT_OUTPUT_PATH="$preflight_output" \
    TESTED_COMMIT="$tested_commit" \
    TESTED_TREE="$tested_tree" \
    LEGACY_CONCLUSION=pass \
    LEGACY_JOB_STATUS="$legacy_job_status" \
    GITHUB_STEP_SUMMARY="$preflight_summary" \
    GITHUB_OUTPUT="$preflight_github_output" \
    sh "$collector"; then
    fail "$case_name preflight did not report cleanly"
  fi

  [ ! -e "$preflight_output" ] || fail "$case_name preflight published canonical records"
  grep -F "result-conclusion=evidence_unavailable" "$preflight_github_output" >/dev/null
  grep -F "records-published=false" "$preflight_github_output" >/dev/null
  grep -F "parity=$expected_parity" "$preflight_github_output" >/dev/null
  grep -F 'unavailable-checks=["actions.contract"]' "$preflight_github_output" >/dev/null
  grep -F "Canonical records: unavailable" "$preflight_summary" >/dev/null

  if [ "$contract_mode" = enforce ]; then
    grep -F "The verification contract gate controls the final consequence; legacy Wiki step outcomes are collected." \
      "$preflight_summary" >/dev/null
    if grep -F "Existing Wiki steps keep their current consequences." "$preflight_summary" >/dev/null; then
      fail "$case_name enforce preflight summary claimed legacy consequences were unchanged"
    fi
  else
    grep -F "Existing Wiki steps keep their current consequences." "$preflight_summary" >/dev/null
  fi
}

assert_preflight_report invalid-mode invalid merge "$commit" "$tree"
assert_preflight_report invalid-target observe invalid "$commit" "$tree"
assert_preflight_report invalid-identity observe merge invalid "$tree"
assert_preflight_report tree-resolution observe merge "$commit" ""
assert_preflight_report legacy-failure observe merge invalid "$tree" failure match
assert_preflight_report enforce-invalid-identity enforce merge invalid "$tree"

no_jq_output="$tmpdir/preflight-no-jq.jsonl"
no_jq_summary="$tmpdir/preflight-no-jq.md"
no_jq_github_output="$tmpdir/preflight-no-jq.out"
mkdir -p "$tmpdir/no-tools"
if ! PATH="$tmpdir/no-tools" \
  RESULT_CONTRACT_MODE=observe \
  VERIFICATION_TARGET=merge \
  RESULT_POLICY_PATH="$tmpdir/policy.json" \
  RESULT_RECORDS_DIR="$pass_records" \
  RESULT_OUTPUT_PATH="$no_jq_output" \
  TESTED_COMMIT="$commit" \
  TESTED_TREE="$tree" \
  LEGACY_CONCLUSION=pass \
  LEGACY_JOB_STATUS=success \
  GITHUB_STEP_SUMMARY="$no_jq_summary" \
  GITHUB_OUTPUT="$no_jq_github_output" \
  /bin/sh "$collector"; then
  fail "missing jq preflight did not report cleanly"
fi
[ ! -e "$no_jq_output" ] || fail "missing jq preflight published canonical records"
grep -F "result-conclusion=evidence_unavailable" "$no_jq_github_output" >/dev/null
grep -F "records-published=false" "$no_jq_github_output" >/dev/null
grep -F "Canonical records: unavailable" "$no_jq_summary" >/dev/null

two_document_policy_records="$tmpdir/two-document-policy-records"
mkdir -p "$two_document_policy_records"
write_observation "$two_document_policy_records/approval.json" review.approval satisfied available
write_observation "$two_document_policy_records/frontmatter.json" source.frontmatter satisfied available
{
  cat "$tmpdir/policy.json"
  cat "$tmpdir/policy.json"
} >"$tmpdir/two-document-policy.json"
mv "$tmpdir/two-document-policy.json" "$tmpdir/policy.json"
two_document_policy_paths="$(run_collector two-document-policy "$two_document_policy_records")"
two_document_policy_output="${two_document_policy_paths%%|*}"
two_document_policy_github_output="${two_document_policy_paths##*|}"
jq -s -e '
  length == 1 and
  .[0].check_id == "actions.policy" and
  .[0].owner == "actions-maintainers" and
  .[0].evidence_ref == "actions:invalid-policy"
' "$two_document_policy_output" >/dev/null || fail "multiple policy documents were not rejected as Actions-owned unavailable evidence"
grep -F "result-conclusion=evidence_unavailable" "$two_document_policy_github_output" >/dev/null
write_policy

invalid_policy_records="$tmpdir/invalid-policy-records"
mkdir -p "$invalid_policy_records"
write_observation "$invalid_policy_records/approval.json" review.approval satisfied available
write_observation "$invalid_policy_records/frontmatter.json" source.frontmatter satisfied available
jq '.contract_version = "wiki-verification-policy.v0"' "$tmpdir/policy.json" >"$tmpdir/invalid-policy.json"
mv "$tmpdir/invalid-policy.json" "$tmpdir/policy.json"
invalid_policy_paths="$(run_collector invalid-policy "$invalid_policy_records")"
invalid_policy_output="${invalid_policy_paths%%|*}"
invalid_policy_github_output="${invalid_policy_paths##*|}"
jq -s -e '
  length == 1 and
  .[0].check_id == "actions.policy" and
  .[0].owner == "actions-maintainers" and
  .[0].availability == "unavailable"
' "$invalid_policy_output" >/dev/null || fail "invalid policy was not reported as Actions-owned unavailable evidence"
grep -F "result-conclusion=evidence_unavailable" "$invalid_policy_github_output" >/dev/null

RESULT_CONCLUSION=trusted sh "$enforce_gate"
RESULT_CONCLUSION=trusted_with_advisories sh "$enforce_gate"
if RESULT_CONCLUSION=blocked sh "$enforce_gate" >"$tmpdir/enforce-blocked.log" 2>&1; then
  fail "enforce gate accepted a blocking conclusion"
fi
if RESULT_CONCLUSION=evidence_unavailable sh "$enforce_gate" >"$tmpdir/enforce-unavailable.log" 2>&1; then
  fail "enforce gate accepted unavailable blocking evidence"
fi
if RESULT_CONCLUSION='' sh "$enforce_gate" >"$tmpdir/enforce-empty.log" 2>&1; then
  fail "enforce gate accepted a missing conclusion"
fi

echo "wiki verification minimal contract fixtures ok"
