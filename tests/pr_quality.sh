#!/bin/sh
set -eu

workflow=.github/workflows/pr-quality.yml
self_workflow=.github/workflows/pr-quality-self.yml
template=templates/pull_request_template.md
self_ci=.github/workflows/ci.yml
contract_doc=docs/pr-quality-contract.md

if [ ! -f "$workflow" ]; then
  echo "missing reusable PR quality workflow: $workflow" >&2
  exit 1
fi

if [ ! -f "$self_workflow" ]; then
  echo "missing Actions PR quality self-caller: $self_workflow" >&2
  exit 1
fi

if [ ! -f "$template" ]; then
  echo "missing canonical PR template: $template" >&2
  exit 1
fi

if [ ! -f "$contract_doc" ]; then
  echo "missing PR quality contract documentation: $contract_doc" >&2
  exit 1
fi

grep -F 'After repairing a failed prerequisite, classify the newly triggered gate run; an earlier failure is not the current result.' "$contract_doc" >/dev/null || {
  echo "PR quality contract must require a fresh gate result after prerequisite repair" >&2
  exit 1
}

for heading in \
  "## Outcome" \
  "## Verification" \
  "## Risk and rollback" \
  "## Linear" \
  "## Adversarial review"
do
  grep -Fx "$heading" "$template" >/dev/null || {
    echo "PR template is missing required heading: $heading" >&2
    exit 1
  }
done

grep -F "PR_BODY_REQUIRED:" "$template" >/dev/null || {
  echo "PR template must contain poison placeholders" >&2
  exit 1
}

grep -F '<!-- e0da-pr-body:v1 -->' "$template" >/dev/null || {
  echo "PR template must carry the versioned body marker" >&2
  exit 1
}

for literal in \
  "  workflow_call:" \
  "        default: approved[pr-reviewer]" \
  "    runs-on: \${{ inputs.runner }}" \
  "      group: pr-quality-\${{ github.repository }}-\${{ github.event.pull_request.number }}" \
  "      issues: write" \
  "      pull-requests: write" \
  "    name: Adversarial Review" \
  "      - name: Enforce PR quality contract"
do
  grep -F "$literal" "$workflow" >/dev/null || {
    echo "workflow is missing expected contract text: $literal" >&2
    exit 1
  }
done

if grep -E '^  pull_request(_review)?:' "$workflow" >/dev/null; then
  echo "reusable PR quality workflow must be workflow_call only" >&2
  exit 1
fi

for literal in \
  'name: PR Quality' \
  '  pull_request:' \
  '    types: [opened, edited, reopened, synchronize, ready_for_review]' \
  '  pull_request_review:' \
  '    types: [submitted, edited, dismissed]' \
  '  issues: write' \
  '  pull-requests: write' \
  '    name: PR Quality' \
  '    uses: ./.github/workflows/pr-quality.yml' \
  '      runner: actions-linux-arm64'
do
  grep -F "$literal" "$self_workflow" >/dev/null || {
    echo "self-caller is missing expected contract text: $literal" >&2
    exit 1
  }
done

[ "$(grep -Fxc '      issues: write' "$workflow")" -eq 1 ] || {
  echo "reusable PR quality workflow must request Issues write exactly once" >&2
  exit 1
}
[ "$(grep -Fxc '  issues: write' "$self_workflow")" -eq 1 ] || {
  echo "PR quality caller must request Issues write exactly once" >&2
  exit 1
}
[ "$(grep -Fxc '      pull-requests: write' "$workflow")" -eq 1 ] || {
  echo "reusable PR quality workflow must request Pull requests write exactly once" >&2
  exit 1
}
[ "$(grep -Fxc '  pull-requests: write' "$self_workflow")" -eq 1 ] || {
  echo "PR quality caller must request Pull requests write exactly once" >&2
  exit 1
}
[ "$(grep -Fxc '  issues: write' "$contract_doc")" -eq 1 ] || {
  echo "PR quality adoption contract must request Issues write exactly once" >&2
  exit 1
}
[ "$(grep -Fxc '  pull-requests: write' "$contract_doc")" -eq 1 ] || {
  echo "PR quality adoption contract must request Pull requests write exactly once" >&2
  exit 1
}
if grep -Fx '  pull-requests: read' "$contract_doc" >/dev/null; then
  echo "PR quality adoption contract must not downgrade Pull requests permission" >&2
  exit 1
fi

grep -F '          sh tests/pr_quality.sh' "$self_ci" >/dev/null || {
  echo "Actions fixture CI does not run the PR quality contract fixtures" >&2
  exit 1
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

if grep -E '^    if:' "$workflow" >/dev/null; then
  echo "authoritative PR quality job must run for every declared event" >&2
  exit 1
fi
grep -Fx '      cancel-in-progress: false' "$workflow" >/dev/null || {
  echo "PR quality events must serialize without canceling an allocated runner" >&2
  exit 1
}
if grep -Fx '      cancel-in-progress: true' "$workflow" >/dev/null; then
  echo "PR quality workflow must not cancel an in-progress event" >&2
  exit 1
fi

gate="$tmpdir/pr-quality-gate.sh"
awk '
  $0 == "      - name: Enforce PR quality contract" {
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
' "$workflow" > "$gate"
sh -n "$gate"

mock_bin="$tmpdir/bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/gh" <<'MOCK_GH'
#!/bin/sh
set -eu

if [ "${TEST_REQUIRE_COLOR_SANITIZED:-false}" = true ]; then
  if [ "${NO_COLOR:-}" != 1 ] || [ "${CLICOLOR:-}" != 0 ] || [ "${CLICOLOR_FORCE:-}" != 0 ]; then
    echo "gh observed unsanitized color environment" >&2
    exit 1
  fi
fi

if [ "$1" != "api" ]; then
  echo "unexpected gh command: $*" >&2
  exit 1
fi

case "$2" in
  repos/e0da/actions/pulls/123)
    count=0
    if [ -f "$TEST_PR_CALL_COUNT" ]; then
      count="$(cat "$TEST_PR_CALL_COUNT")"
    fi
    count=$((count + 1))
    printf '%s\n' "$count" > "$TEST_PR_CALL_COUNT"
    case "$count" in
      1) cat "$TEST_PR_BEFORE" ;;
      2) cat "$TEST_PR_AFTER" ;;
      *) cat "$TEST_PR_POST_LABEL" ;;
    esac
    ;;
  repos/e0da/actions/pulls/123/reviews/456)
    cat "$TEST_REVIEW"
    ;;
  repos/e0da/actions/pulls/123/reviews)
    case "$*" in
      *"--slurp"*)
        echo "mock gh does not support --slurp" >&2
        exit 1
        ;;
      *"--paginate --jq .[]"*)
        count=0
        if [ -f "$TEST_REVIEW_LIST_CALL_COUNT" ]; then
          count="$(cat "$TEST_REVIEW_LIST_CALL_COUNT")"
        fi
        count=$((count + 1))
        printf '%s\n' "$count" > "$TEST_REVIEW_LIST_CALL_COUNT"
        if [ "$count" -eq 1 ]; then
          jq -c '.[][]' "$TEST_REVIEW_PAGES"
        else
          jq -c '.[][]' "$TEST_REVIEW_PAGES_POST_LABEL"
        fi
        ;;
      *)
        echo "unexpected review-list arguments: $*" >&2
        exit 1
        ;;
    esac
    ;;
  repos/e0da/actions/issues/123/labels)
    case "$*" in
      *"--method POST"*)
        printf '%s\n' "$*" >> "$TEST_LABEL_LOG"
        ;;
      *)
        cat "$TEST_LIVE_LABELS"
        ;;
    esac
    ;;
  repos/e0da/actions/issues/123/labels/approved%5Bpr-reviewer%5D)
    printf '%s\n' "$*" >> "$TEST_LABEL_LOG"
    ;;
  *)
    echo "unexpected gh api path: $2" >&2
    exit 1
    ;;
esac
MOCK_GH
chmod +x "$mock_bin/gh"

sha256_text() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{ print $1 }'
  else
    shasum -a 256 | awk '{ print $1 }'
  fi
}

head_sha=1111111111111111111111111111111111111111
new_head_sha=2222222222222222222222222222222222222222
pr_title='feat: enforce PR quality contract'
review_url=https://github.com/e0da/actions/pull/123#pullrequestreview-456
evidence='[{"kind":"command","result":"pass","subject":"sh tests/pr_quality.sh"}]'
evidence_digest="sha256:$(printf '%s' "$evidence" | sha256_text)"
rubric_material='{"checks":["correctness","verification","risk","scope"],"id":"e0da.adversarial-pr-review","version":"1"}'
rubric_digest="sha256:$(printf '%s' "$rubric_material" | sha256_text)"

valid_body() {
  cat <<EOF
<!-- e0da-pr-body:v1 -->

## Outcome

Ship a reusable, exact-head PR quality contract.

## Verification

The focused contract fixtures pass locally and in Actions self-CI.

## Risk and rollback

Risk is isolated to PR metadata validation; revert the caller workflow to roll back.

## Linear

E0D-1667

## Adversarial review

$review_url
EOF
}

receipt() {
  receipt_head="$1"
  reviewer_login="$2"
  findings="$3"
  digest="$4"

  jq -cn \
    --arg head "$receipt_head" \
    --arg login "$reviewer_login" \
    --arg findings "$findings" \
    --arg digest "$digest" \
    --arg rubric_digest "$rubric_digest" \
    --arg pr_metadata_digest "$pr_metadata_digest" \
    --argjson evidence "$evidence" \
    '{
      schema: "e0da.adversarial-review-receipt/v1",
      repository: "e0da/actions",
      pull_request: 123,
      head_sha: $head,
      pr_metadata_digest: $pr_metadata_digest,
      reviewer: {id: "agent:hypatia", github_login: $login},
      session: {id: "session:pr-quality-test", tool: "codex"},
      rubric: {
        id: "e0da.adversarial-pr-review",
        version: "1",
        digest: $rubric_digest,
        checks: ["correctness", "verification", "risk", "scope"]
      },
      verdict: "APPROVE",
      findings: ($findings | fromjson),
      evidence: $evidence,
      evidence_digest: $digest
    }'
}

review_body() {
  cat <<EOF
Recommendation: Approve

Blockers:
- none

Nits:
- none

<!-- E0DA_ADVERSARIAL_REVIEW_RECEIPT_V1
$1
-->
EOF
}

normalized_section() {
  section_name="$1"
  body_file="$2"
  awk -v heading="## $section_name" '
    $0 == heading { active=1; next }
    active && /^## / { exit }
    active { print }
  ' "$body_file" |
    jq -Rrs 'gsub("\\r\\n?"; "\\n") | gsub("^[ \\t\\n]+|[ \\t\\n]+$"; "")'
}

metadata_digest_for() {
  metadata_body="$1"
  metadata_title="$2"
  metadata_body_file="$tmpdir/metadata-body.md"
  printf '%s\n' "$metadata_body" > "$metadata_body_file"
  metadata_outcome="$(normalized_section Outcome "$metadata_body_file")"
  metadata_verification="$(normalized_section Verification "$metadata_body_file")"
  metadata_risk="$(normalized_section 'Risk and rollback' "$metadata_body_file")"
  metadata_linear="$(normalized_section Linear "$metadata_body_file")"
  metadata_material="$(
    jq -cnS \
      --arg title "$metadata_title" \
      --arg outcome "$metadata_outcome" \
      --arg verification "$metadata_verification" \
      --arg risk "$metadata_risk" \
      --arg linear "$metadata_linear" \
      '{
        body_version: "e0da-pr-body:v1",
        title: $title,
        sections: {
          "Outcome": $outcome,
          "Verification": $verification,
          "Risk and rollback": $risk,
          "Linear": $linear,
          "Adversarial review": "<native-review>"
        }
      }'
  )"
  printf '%s' "$metadata_material" | sha256_text
}

run_gate() {
  case_name="$1"
  case_body="$2"
  case_before_head="$3"
  case_after_head="$4"
  case_pr_author="$5"
  case_review_state="$6"
  case_review_commit="$7"
  case_review_user="$8"
  case_review_text="$9"
  case_reviews="${10:-}"
  case_review_pages="${11:-}"
  case_post_label_head="${12:-$case_after_head}"
  case_post_label_review_pages="${13:-}"

  before_file="$tmpdir/$case_name.pr-before.json"
  after_file="$tmpdir/$case_name.pr-after.json"
  post_label_file="$tmpdir/$case_name.pr-post-label.json"
  review_file="$tmpdir/$case_name.review.json"
  reviews_file="$tmpdir/$case_name.reviews.json"
  review_pages_file="$tmpdir/$case_name.review-pages.json"
  post_label_review_pages_file="$tmpdir/$case_name.review-pages-post-label.json"
  output_file="$tmpdir/$case_name.output"
  label_log="$tmpdir/$case_name.labels"
  call_count="$tmpdir/$case_name.pr-count"
  require_color_sanitized=false
  if [ "$case_name" = color_sanitized ]; then
    require_color_sanitized=true
  fi

  jq -cn \
    --arg body "$case_body" \
    --arg title "$pr_title" \
    --arg head "$case_before_head" \
    --arg author "$case_pr_author" \
    '{body: $body, title: $title, head: {sha: $head}, user: {login: $author}}' > "$before_file"
  jq -cn \
    --arg body "$case_body" \
    --arg title "$pr_title" \
    --arg head "$case_after_head" \
    --arg author "$case_pr_author" \
    '{body: $body, title: $title, head: {sha: $head}, user: {login: $author}}' > "$after_file"
  jq -cn \
    --arg body "$case_body" \
    --arg title "$pr_title" \
    --arg head "$case_post_label_head" \
    --arg author "$case_pr_author" \
    '{body: $body, title: $title, head: {sha: $head}, user: {login: $author}}' > "$post_label_file"
  jq -cn \
    --arg body "$case_review_text" \
    --arg state "$case_review_state" \
    --arg commit "$case_review_commit" \
    --arg user "$case_review_user" \
    --arg url "$review_url" \
    '{id: 456, submitted_at: "2026-09-02T22:00:00Z", body: $body, state: $state, commit_id: $commit, user: {login: $user}, html_url: $url}' > "$review_file"
  if [ -n "$case_reviews" ]; then
    printf '%s\n' "$case_reviews" > "$reviews_file"
  else
    jq -s '.' "$review_file" > "$reviews_file"
  fi
  if [ -n "$case_review_pages" ]; then
    printf '%s\n' "$case_review_pages" > "$review_pages_file"
  else
    jq -s '.' "$reviews_file" > "$review_pages_file"
  fi
  if [ -n "$case_post_label_review_pages" ]; then
    printf '%s\n' "$case_post_label_review_pages" > "$post_label_review_pages_file"
  else
    cp "$review_pages_file" "$post_label_review_pages_file"
  fi
  : > "$label_log"

  (
    PATH="$mock_bin:$PATH" \
      NO_COLOR=1 \
      CLICOLOR=1 \
      CLICOLOR_FORCE=1 \
      TEST_REQUIRE_COLOR_SANITIZED="$require_color_sanitized" \
      GH_TOKEN=fake-token \
      REPOSITORY=e0da/actions \
      PULL_REQUEST_NUMBER=123 \
      PROJECTION_LABEL='approved[pr-reviewer]' \
      TEST_PR_BEFORE="$before_file" \
      TEST_PR_AFTER="$after_file" \
      TEST_PR_POST_LABEL="$post_label_file" \
      TEST_REVIEW="$review_file" \
      TEST_REVIEWS="$reviews_file" \
      TEST_REVIEW_PAGES="$review_pages_file" \
      TEST_REVIEW_PAGES_POST_LABEL="$post_label_review_pages_file" \
      TEST_REVIEW_LIST_CALL_COUNT="$tmpdir/$case_name.review-list-count" \
      TEST_PR_CALL_COUNT="$call_count" \
      TEST_LABEL_LOG="$label_log" \
      TEST_LIVE_LABELS="$tmpdir/$case_name.live-labels" \
      RUNNER_TEMP="$tmpdir/$case_name.runner" \
      GITHUB_STEP_SUMMARY="$tmpdir/$case_name.summary" \
      sh "$gate"
  ) > "$output_file" 2>&1
}

expect_success() {
  name="$1"
  shift
  if ! run_gate "$name" "$@"; then
    cat "$tmpdir/$name.output" >&2
    echo "expected success: $name" >&2
    exit 1
  fi
}

expect_failure() {
  name="$1"
  expected="$2"
  shift 2
  if run_gate "$name" "$@"; then
    echo "expected failure: $name" >&2
    exit 1
  fi
  grep -F "$expected" "$tmpdir/$name.output" >/dev/null || {
    cat "$tmpdir/$name.output" >&2
    echo "missing expected failure text for $name: $expected" >&2
    exit 1
  }
  grep -F -- "--method DELETE" "$tmpdir/$name.labels" >/dev/null || {
    echo "failed gate did not remove its projection label: $name" >&2
    exit 1
  }
  if grep -F "approved%5Be0da%5D" "$tmpdir/$name.labels" >/dev/null; then
    echo "gate touched reserved human approval label: $name" >&2
    exit 1
  fi
}

body="$(valid_body)"
pr_metadata_digest="sha256:$(metadata_digest_for "$body" "$pr_title")"
valid_approved_receipt="$(receipt "$head_sha" hypatia-bot '[]' "$evidence_digest")"
valid_commented_receipt="$(receipt "$head_sha" e0da '[]' "$evidence_digest")"
valid_independent_receipt="$valid_approved_receipt"

for case_name in independent_approved color_sanitized commented_review poison_placeholder \
  missing_body_marker missing_section comment_only_section stale_receipt \
  stale_native_review malformed_receipt missing_rubric_version \
  invalid_rubric_digest foreign_receipt changes_requested unresolved_finding \
  digest_mismatch foreign_commented head_race missing_receipt_block \
  duplicate_receipt_block repository_mismatch pull_request_mismatch \
  metadata_tamper later_changes_requested resolved_changes_requested \
  comment_does_not_clear_changes json_only_review weak_rubric \
  duplicate_body_heading recommendation_mismatch \
  hidden_pr_body hidden_review unresolved_human_blocker multipage_reviews empty_review_list \
  fenced_pr_body fenced_review \
  post_label_head_race post_label_changes_requested flexible_review_layout \
  extra_review_prose long_backtick_fence long_tilde_fence longer_fence_closer \
  indented_backtick_closer indented_tilde_closer \
  comment_prefixed_backtick_closer comment_prefixed_indented_tilde_closer
do
  printf '%s\n' 'approved[pr-reviewer]' > "$tmpdir/$case_name.live-labels"
done

expect_success \
  independent_approved \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_approved_receipt")"
grep -F -- "--method POST" "$tmpdir/independent_approved.labels" >/dev/null

expect_success \
  color_sanitized \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_approved_receipt")"

expect_success \
  commented_review \
  "$body" "$head_sha" "$head_sha" e0da \
  COMMENTED "$head_sha" e0da "$(review_body "$valid_commented_receipt")"

poisoned_body="$(printf '%s\nPR_BODY_REQUIRED:OUTCOME\n' "$body")"
expect_failure \
  poison_placeholder \
  "replace every PR_BODY_REQUIRED:<SECTION> placeholder" \
  "$poisoned_body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

missing_marker_body="$(printf '%s\n' "$body" | sed '/^<!-- e0da-pr-body:v1 -->$/d')"
expect_failure \
  missing_body_marker \
  "PR body is missing <!-- e0da-pr-body:v1 -->" \
  "$missing_marker_body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

missing_linear_body="$(printf '%s\n' "$body" | sed '/^## Linear$/,/^## Adversarial review$/ { /^## Linear$/d; /^E0D-1667$/d; }')"
expect_failure \
  missing_section \
  "missing required non-empty section: Linear" \
  "$missing_linear_body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

comment_only_outcome_body="$(printf '%s\n' "$body" | awk '
  /^## Outcome$/ { print; in_outcome=1; next }
  in_outcome && /^## / { print "<!-- outcome intentionally absent -->"; in_outcome=0 }
  !in_outcome { print }
')"
expect_failure \
  comment_only_section \
  "missing required non-empty section: Outcome" \
  "$comment_only_outcome_body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

stale_receipt="$(receipt "$new_head_sha" hypatia-bot '[]' "$evidence_digest")"
expect_failure \
  stale_receipt \
  "receipt head does not match live PR head" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$stale_receipt")"

expect_failure \
  stale_native_review \
  "native review commit does not match live PR head" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$new_head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

expect_failure \
  malformed_receipt \
  "review receipt is not valid JSON" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body '{not-json}')"

expect_failure \
  missing_receipt_block \
  "native review must contain exactly one v1 adversarial review receipt block" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot 'Recommendation: Approve

Blockers:
- none

Nits:
- none'

duplicate_review_body="$(review_body "$valid_independent_receipt")
<!-- E0DA_ADVERSARIAL_REVIEW_RECEIPT_V1
$valid_independent_receipt
-->"
expect_failure \
  duplicate_receipt_block \
  "native review must contain exactly one v1 adversarial review receipt block" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$duplicate_review_body"

json_only_review="<!-- E0DA_ADVERSARIAL_REVIEW_RECEIPT_V1
$valid_independent_receipt
-->"
expect_failure \
  json_only_review \
  "native review is missing canonical Recommendation: Approve" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$json_only_review"

request_changes_review="$(review_body "$valid_independent_receipt" | awk '
  !replaced && $0 == "Recommendation: Approve" { print "Recommendation: Request changes"; replaced=1; next }
  { print }
')"
expect_failure \
  recommendation_mismatch \
  "native review is missing canonical Recommendation: Approve" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$request_changes_review"

hidden_body="<!-- e0da-pr-body:v1 -->
<!--
$(printf '%s\n' "$body" | sed '/^<!-- e0da-pr-body:v1 -->$/d')
-->"
expect_failure \
  hidden_pr_body \
  "missing required non-empty section: Outcome" \
  "$hidden_body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

hidden_human_review="<!--
Recommendation: Approve

Blockers:
- none

Nits:
- none
-->

<!-- E0DA_ADVERSARIAL_REVIEW_RECEIPT_V1
$valid_independent_receipt
-->"
expect_failure \
  hidden_review \
  "native review is missing canonical Recommendation: Approve" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$hidden_human_review"

fenced_body="<!-- e0da-pr-body:v1 -->

\`\`\`
$(printf '%s\n' "$body" | sed '/^<!-- e0da-pr-body:v1 -->$/d')
\`\`\`"
expect_failure \
  fenced_pr_body \
  "missing required non-empty section: Outcome" \
  "$fenced_body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

long_backtick_body="<!-- e0da-pr-body:v1 -->

\`\`\`\`
This four-backtick fence remains open in CommonMark.
\`\`\`
$(printf '%s\n' "$body" | sed '/^<!-- e0da-pr-body:v1 -->$/d')"
expect_failure \
  long_backtick_fence \
  "PR body contains an unclosed HTML comment or code fence" \
  "$long_backtick_body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

long_tilde_body="<!-- e0da-pr-body:v1 -->

~~~~
This four-tilde fence remains open in CommonMark.
~~~
$(printf '%s\n' "$body" | sed '/^<!-- e0da-pr-body:v1 -->$/d')"
expect_failure \
  long_tilde_fence \
  "PR body contains an unclosed HTML comment or code fence" \
  "$long_tilde_body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

longer_closer_body="<!-- e0da-pr-body:v1 -->

\`\`\`
## Outcome
This example remains hidden.
\`\`\`\`
$(printf '%s\n' "$body" | sed '/^<!-- e0da-pr-body:v1 -->$/d')"
expect_success \
  longer_fence_closer \
  "$longer_closer_body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

indented_backtick_closer_body="<!-- e0da-pr-body:v1 -->

\`\`\`\`
This fence remains open because its apparent closer is indented four spaces.
    \`\`\`\`
$(printf '%s\n' "$body" | sed '/^<!-- e0da-pr-body:v1 -->$/d')"
expect_failure \
  indented_backtick_closer \
  "PR body contains an unclosed HTML comment or code fence" \
  "$indented_backtick_closer_body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

indented_tilde_closer_body="<!-- e0da-pr-body:v1 -->

~~~~
This fence remains open because its apparent closer is indented four spaces.
    ~~~~
$(printf '%s\n' "$body" | sed '/^<!-- e0da-pr-body:v1 -->$/d')"
expect_failure \
  indented_tilde_closer \
  "PR body contains an unclosed HTML comment or code fence" \
  "$indented_tilde_closer_body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

comment_prefixed_indented_tilde_closer_body="<!-- e0da-pr-body:v1 -->

~~~~
The apparent closer contains indented literal fenced content.
   <!-- -->~~~~
$(printf '%s\n' "$body" | sed '/^<!-- e0da-pr-body:v1 -->$/d')"
expect_failure \
  comment_prefixed_indented_tilde_closer \
  "PR body contains an unclosed HTML comment or code fence" \
  "$comment_prefixed_indented_tilde_closer_body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

comment_prefixed_backtick_closer_body="<!-- e0da-pr-body:v1 -->

\`\`\`\`
The apparent closer contains literal fenced content.
<!-- -->\`\`\`\`
$(printf '%s\n' "$body" | sed '/^<!-- e0da-pr-body:v1 -->$/d')"
expect_failure \
  comment_prefixed_backtick_closer \
  "PR body contains an unclosed HTML comment or code fence" \
  "$comment_prefixed_backtick_closer_body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

fenced_human_review="\`\`\`
Recommendation: Approve

Blockers:
- none

Nits:
- none
\`\`\`

<!-- E0DA_ADVERSARIAL_REVIEW_RECEIPT_V1
$valid_independent_receipt
-->"
expect_failure \
  fenced_review \
  "native review is missing canonical Recommendation: Approve" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$fenced_human_review"

unresolved_human_review="$(review_body "$valid_independent_receipt" | awk '
  !replaced && $0 == "- none" { print "- F1 remains unresolved"; replaced=1; next }
  { print }
')"
expect_failure \
  unresolved_human_blocker \
  "native review Blockers: must normalize to - none" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$unresolved_human_review"

wrong_order_review="Recommendation: Approve

Nits:
- none

Blockers:
- none

<!-- E0DA_ADVERSARIAL_REVIEW_RECEIPT_V1
$valid_independent_receipt
-->"
expect_success \
  flexible_review_layout \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$wrong_order_review"

extra_prose_review="$(review_body "$valid_independent_receipt")

Review narrative that is outside the canonical control surface."
expect_success \
  extra_review_prose \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$extra_prose_review"

missing_rubric_version_receipt="$(printf '%s' "$valid_independent_receipt" | jq -c 'del(.rubric.version)')"
expect_failure \
  missing_rubric_version \
  "review receipt has an invalid rubric contract" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$missing_rubric_version_receipt")"

invalid_rubric_digest_receipt="$(printf '%s' "$valid_independent_receipt" | jq -c '.rubric.digest = "sha256:0000000000000000000000000000000000000000000000000000000000000000"')"
expect_failure \
  invalid_rubric_digest \
  "review rubric digest does not match canonical rubric" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$invalid_rubric_digest_receipt")"

weak_rubric_material='{"checks":["correctness"],"id":"e0da.adversarial-pr-review","version":"1"}'
weak_rubric_digest="sha256:$(printf '%s' "$weak_rubric_material" | sha256_text)"
weak_rubric_receipt="$(printf '%s' "$valid_independent_receipt" | jq -c --arg digest "$weak_rubric_digest" '.rubric.checks = ["correctness"] | .rubric.digest = $digest')"
expect_failure \
  weak_rubric \
  "review receipt does not use the canonical adversarial rubric" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$weak_rubric_receipt")"

foreign_receipt="$(receipt "$head_sha" foreign-bot '[]' "$evidence_digest")"
expect_failure \
  foreign_receipt \
  "receipt reviewer does not match native review publisher" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$foreign_receipt")"

expect_failure \
  changes_requested \
  "native review state CHANGES_REQUESTED is not acceptable" \
  "$body" "$head_sha" "$head_sha" e0da \
  CHANGES_REQUESTED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

unresolved_findings='[{"id":"F1","severity":"high","status":"open","resolution":""}]'
unresolved_receipt="$(receipt "$head_sha" hypatia-bot "$unresolved_findings" "$evidence_digest")"
expect_failure \
  unresolved_finding \
  "review receipt contains unresolved findings" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$unresolved_receipt")"

wrong_digest="sha256:$(printf '%064d' 0)"
digest_mismatch_receipt="$(receipt "$head_sha" hypatia-bot '[]' "$wrong_digest")"
expect_failure \
  digest_mismatch \
  "review evidence digest does not match canonical evidence" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$digest_mismatch_receipt")"

foreign_commented_receipt="$(receipt "$head_sha" hypatia-bot '[]' "$evidence_digest")"
expect_success \
  foreign_commented \
  "$body" "$head_sha" "$head_sha" e0da \
  COMMENTED "$head_sha" hypatia-bot "$(review_body "$foreign_commented_receipt")"

expect_failure \
  head_race \
  "PR head changed while the quality contract was running" \
  "$body" "$head_sha" "$new_head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

expect_failure \
  post_label_head_race \
  "PR head changed after projection label update" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")" \
  '' '' "$new_head_sha"

post_label_changes_pages="$(jq -cn \
  --arg head "$head_sha" \
  '[
    [
      {id: 456, submitted_at: "2026-09-02T22:00:00Z", state: "APPROVED", commit_id: $head, user: {login: "hypatia-bot"}},
      {id: 457, submitted_at: "2026-09-02T22:01:00Z", state: "CHANGES_REQUESTED", commit_id: $head, user: {login: "peirce-bot"}}
    ]
  ]')"
expect_failure \
  post_label_changes_requested \
  "a reviewer's latest current-head state is CHANGES_REQUESTED" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")" \
  '' '' "$head_sha" "$post_label_changes_pages"

repository_mismatch_receipt="$(printf '%s' "$valid_independent_receipt" | jq -c '.repository = "e0da/other"')"
expect_failure \
  repository_mismatch \
  "receipt repository does not match the live PR" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$repository_mismatch_receipt")"

pull_request_mismatch_receipt="$(printf '%s' "$valid_independent_receipt" | jq -c '.pull_request = 999')"
expect_failure \
  pull_request_mismatch \
  "receipt pull request does not match the live PR" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$pull_request_mismatch_receipt")"

tampered_body="$(printf '%s\n' "$body" | sed 's/Ship a reusable, exact-head PR quality contract\./Ship a weaker PR quality contract./')"
expect_failure \
  metadata_tamper \
  "receipt PR metadata digest does not match live title and body" \
  "$tampered_body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

duplicate_outcome_body="$(printf '%s\n\n## Outcome\n\nA second interpretation.\n' "$body")"
expect_failure \
  duplicate_body_heading \
  "required PR body heading must appear exactly once: Outcome" \
  "$duplicate_outcome_body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")"

later_changes_reviews="$(jq -cn \
  --arg head "$head_sha" \
  '[
    {id: 456, submitted_at: "2026-09-02T22:00:00Z", state: "APPROVED", commit_id: $head, user: {login: "hypatia-bot"}},
    {id: 457, submitted_at: "2026-09-02T22:01:00Z", state: "CHANGES_REQUESTED", commit_id: $head, user: {login: "peirce-bot"}}
  ]')"
expect_failure \
  later_changes_requested \
  "a reviewer's latest current-head state is CHANGES_REQUESTED" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")" \
  "$later_changes_reviews"

resolved_changes_reviews="$(jq -cn \
  --arg head "$head_sha" \
  '[
    {id: 455, submitted_at: "2026-09-02T21:59:00Z", state: "CHANGES_REQUESTED", commit_id: $head, user: {login: "hypatia-bot"}},
    {id: 456, submitted_at: "2026-09-02T22:00:00Z", state: "APPROVED", commit_id: $head, user: {login: "hypatia-bot"}}
  ]')"
expect_success \
  resolved_changes_requested \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")" \
  "$resolved_changes_reviews"

comment_after_changes_reviews="$(jq -cn \
  --arg head "$head_sha" \
  '[
    {id: 456, submitted_at: "2026-09-02T22:00:00Z", state: "APPROVED", commit_id: $head, user: {login: "hypatia-bot"}},
    {id: 457, submitted_at: "2026-09-02T22:01:00Z", state: "CHANGES_REQUESTED", commit_id: $head, user: {login: "peirce-bot"}},
    {id: 458, submitted_at: "2026-09-02T22:02:00Z", state: "COMMENTED", commit_id: $head, user: {login: "peirce-bot"}}
  ]')"
expect_failure \
  comment_does_not_clear_changes \
  "a reviewer's latest current-head state is CHANGES_REQUESTED" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")" \
  "$comment_after_changes_reviews"

multipage_review_pages="$(jq -cn \
  --arg head "$head_sha" \
  '[
    [
      {id: 456, submitted_at: "2026-09-02T22:00:00Z", state: "APPROVED", commit_id: $head, user: {login: "hypatia-bot"}}
    ],
    [
      {id: 457, submitted_at: "2026-09-02T22:01:00Z", state: "COMMENTED", commit_id: $head, user: {login: "peirce-bot"}}
    ]
  ]')"
expect_success \
  multipage_reviews \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")" \
  '' "$multipage_review_pages"

expect_failure \
  empty_review_list \
  "linked native review is absent or changed in the current review list" \
  "$body" "$head_sha" "$head_sha" e0da \
  APPROVED "$head_sha" hypatia-bot "$(review_body "$valid_independent_receipt")" \
  '' '[[]]'

echo "PR quality contract fixtures ok"
