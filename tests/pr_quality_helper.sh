#!/bin/sh
set -eu

helper=scripts/pr-quality-review
self_ci=.github/workflows/ci.yml

[ -x "$helper" ] || {
  echo "missing executable PR quality review helper: $helper" >&2
  exit 1
}

grep -F '          sh tests/pr_quality_helper.sh' "$self_ci" >/dev/null || {
  echo "Actions fixture CI does not run the PR quality helper fixtures" >&2
  exit 1
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM
mock_bin="$tmpdir/bin"
mkdir -p "$mock_bin"

head_sha=1111111111111111111111111111111111111111
review_url=https://github.com/e0da/actions/pull/123#pullrequestreview-456

cat > "$tmpdir/pr.json" <<EOF
{
  "title": "feat: enforce PR quality contract",
  "body": "<!-- e0da-pr-body:v1 -->\n\n## Outcome\n\nShip the contract.\n\n## Verification\n\nFocused fixtures pass.\n\n## Risk and rollback\n\nRevert the caller.\n\n## Linear\n\nE0D-1667\n\n## Adversarial review\n\nPR_BODY_REQUIRED:ADVERSARIAL_REVIEW",
  "head": {"sha": "$head_sha"},
  "user": {"login": "e0da"}
}
EOF

cat > "$tmpdir/review.md" <<'EOF'
Recommendation: Approve

Blockers:
- none

Nits:
- none
EOF

cat > "$tmpdir/evidence.json" <<'EOF'
[
  {
    "kind": "command",
    "subject": "sh tests/pr_quality.sh",
    "result": "pass"
  }
]
EOF

cat > "$mock_bin/gh" <<'MOCK_GH'
#!/bin/sh
set -eu

if [ "${TEST_REQUIRE_COLOR_SANITIZED:-false}" = true ]; then
  if [ "${NO_COLOR:-}" != 1 ] || [ "${CLICOLOR:-}" != 0 ] || [ "${CLICOLOR_FORCE:-}" != 0 ]; then
    echo "gh observed unsanitized color environment" >&2
    exit 1
  fi
fi

case "$1:$2" in
  repo:view)
    echo e0da/actions
    ;;
  pr:view)
    echo 123
    ;;
  api:user)
    echo "$TEST_GITHUB_LOGIN"
    ;;
  api:repos/e0da/actions/pulls/123)
    case "$*" in
      *"--method PATCH"*)
        while [ "$#" -gt 0 ]; do
          if [ "$1" = --input ]; then
            cp "$2" "$TEST_PATCH_PAYLOAD"
            break
          fi
          shift
        done
        printf '%s\n' PATCH >> "$TEST_MUTATION_LOG"
        if [ "$TEST_PATCH_FAIL" = true ]; then
          echo "simulated PATCH failure" >&2
          exit 1
        fi
        echo '{}'
        ;;
      *)
        pr_count=0
        if [ -f "$TEST_PR_CALL_COUNT" ]; then
          pr_count="$(cat "$TEST_PR_CALL_COUNT")"
        fi
        pr_count=$((pr_count + 1))
        printf '%s\n' "$pr_count" > "$TEST_PR_CALL_COUNT"
        if [ "$pr_count" -eq 1 ]; then
          cat "$TEST_PR_INITIAL"
        else
          cat "$TEST_PR_LIVE"
        fi
        ;;
    esac
    ;;
  api:repos/e0da/actions/pulls/123/reviews)
    case "$*" in
      *"--method POST"*)
        while [ "$#" -gt 0 ]; do
          if [ "$1" = --input ]; then
            cp "$2" "$TEST_REVIEW_PAYLOAD"
            break
          fi
          shift
        done
        printf '%s\n' POST >> "$TEST_MUTATION_LOG"
        jq -cn --arg url "$TEST_REVIEW_URL" '{html_url: $url}'
        ;;
      *"--slurp"*)
        echo "mock gh does not support --slurp" >&2
        exit 1
        ;;
      *"--paginate --jq .[]"*)
        jq -c '.[][]' "$TEST_REVIEW_PAGES"
        ;;
      *)
        echo "unexpected review-list arguments: $*" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "unexpected gh command: $*" >&2
    exit 1
    ;;
esac
MOCK_GH
chmod +x "$mock_bin/gh"

run_helper() {
  name="$1"
  login="$2"
  review_file="$3"
  live_pr="${4:-$tmpdir/pr.json}"
  existing_pages="${5:-}"
  patch_fail="${6:-false}"
  require_color_sanitized=false
  if [ "$name" = color_sanitized ]; then
    require_color_sanitized=true
  fi
  output_file="$tmpdir/$name.output"
  review_payload="$tmpdir/$name.review-payload.json"
  patch_payload="$tmpdir/$name.patch-payload.json"
  review_pages="$tmpdir/$name.review-pages.json"
  mutation_log="$tmpdir/$name.mutations"
  pr_call_count="$tmpdir/$name.pr-count"
  : > "$mutation_log"
  if [ -n "$existing_pages" ]; then
    printf '%s\n' "$existing_pages" > "$review_pages"
  else
    printf '[[]]\n' > "$review_pages"
  fi

  (
    PATH="$mock_bin:$PATH" \
      NO_COLOR=1 \
      CLICOLOR=1 \
      CLICOLOR_FORCE=1 \
      TEST_REQUIRE_COLOR_SANITIZED="$require_color_sanitized" \
      TEST_GITHUB_LOGIN="$login" \
      TEST_PR_INITIAL="$tmpdir/pr.json" \
      TEST_PR_LIVE="$live_pr" \
      TEST_PR_CALL_COUNT="$pr_call_count" \
      TEST_REVIEW_URL="$review_url" \
      TEST_REVIEW_PAYLOAD="$review_payload" \
      TEST_REVIEW_PAGES="$review_pages" \
      TEST_PATCH_PAYLOAD="$patch_payload" \
      TEST_MUTATION_LOG="$mutation_log" \
      TEST_PATCH_FAIL="$patch_fail" \
      "$helper" \
        --reviewer agent:hypatia \
        --session session:pr-quality-helper-test \
        --review-file "$review_file" \
        --evidence-file "$tmpdir/evidence.json"
  ) > "$output_file" 2>&1
}

if ! run_helper commented e0da "$tmpdir/review.md"; then
  cat "$tmpdir/commented.output" >&2
  echo "helper failed to enumerate an empty paginated review list" >&2
  exit 1
fi
grep -Fx "$review_url" "$tmpdir/commented.output" >/dev/null
jq -e '.event == "COMMENT" and .commit_id == "1111111111111111111111111111111111111111"' \
  "$tmpdir/commented.review-payload.json" >/dev/null
jq -r '.body' "$tmpdir/commented.review-payload.json" > "$tmpdir/published-review.md"
grep -F '<!-- E0DA_ADVERSARIAL_REVIEW_RECEIPT_V1' "$tmpdir/published-review.md" >/dev/null
awk '
  $0 == "<!-- E0DA_ADVERSARIAL_REVIEW_RECEIPT_V1" { active=1; next }
  active && $0 == "-->" { exit }
  active { print }
' "$tmpdir/published-review.md" > "$tmpdir/receipt.json"
jq -e '
  .repository == "e0da/actions" and
  .pull_request == 123 and
  .head_sha == "1111111111111111111111111111111111111111" and
  .reviewer.github_login == "e0da" and
  .session.id == "session:pr-quality-helper-test" and
  .rubric.id == "e0da.adversarial-pr-review" and
  .rubric.version == "1" and
  .verdict == "APPROVE"
' "$tmpdir/receipt.json" >/dev/null

rubric_material="$(jq -cS '.rubric | del(.digest)' "$tmpdir/receipt.json")"
rubric_digest="sha256:$(printf '%s' "$rubric_material" | shasum -a 256 | awk '{ print $1 }')"
[ "$(jq -r '.rubric.digest' "$tmpdir/receipt.json")" = "$rubric_digest" ]
evidence_material="$(jq -cS '.evidence' "$tmpdir/receipt.json")"
evidence_digest="sha256:$(printf '%s' "$evidence_material" | shasum -a 256 | awk '{ print $1 }')"
[ "$(jq -r '.evidence_digest' "$tmpdir/receipt.json")" = "$evidence_digest" ]

patched_body="$(jq -r '.body' "$tmpdir/commented.patch-payload.json")"
printf '%s\n' "$patched_body" | grep -Fx '<!-- e0da-pr-body:v1 -->' >/dev/null
printf '%s\n' "$patched_body" | grep -Fx "$review_url" >/dev/null
if printf '%s\n' "$patched_body" | grep -F 'PR_BODY_REQUIRED:' >/dev/null; then
  echo "helper left a poison placeholder in the patched PR body" >&2
  exit 1
fi

run_helper empty_review_list e0da "$tmpdir/review.md" "$tmpdir/pr.json" '[[], []]'
grep -Fx POST "$tmpdir/empty_review_list.mutations" >/dev/null

run_helper approved hypatia-bot "$tmpdir/review.md"
jq -e '.event == "APPROVE"' "$tmpdir/approved.review-payload.json" >/dev/null

if ! run_helper color_sanitized e0da "$tmpdir/review.md"; then
  cat "$tmpdir/color_sanitized.output" >&2
  echo "helper did not sanitize the gh color environment" >&2
  exit 1
fi
grep -Fx "$review_url" "$tmpdir/color_sanitized.output" >/dev/null

cat > "$tmpdir/incomplete-review.md" <<'EOF'
Recommendation: Approve
EOF
if run_helper invalid_review e0da "$tmpdir/incomplete-review.md"; then
  echo "helper accepted a review without Blockers and Nits" >&2
  exit 1
fi
grep -F 'review file must contain exactly one Blockers: field' \
  "$tmpdir/invalid_review.output" >/dev/null

sed 's/^Recommendation: Approve$/Recommendation: Request changes/' "$tmpdir/review.md" > "$tmpdir/request-changes-review.md"
if run_helper recommendation_mismatch e0da "$tmpdir/request-changes-review.md"; then
  echo "helper accepted a non-APPROVE human recommendation" >&2
  exit 1
fi
grep -F 'review is missing canonical Recommendation: Approve' \
  "$tmpdir/recommendation_mismatch.output" >/dev/null

cat > "$tmpdir/hidden-review.md" <<'EOF'
<!--
Recommendation: Approve

Blockers:
- none

Nits:
- none
-->
EOF
if run_helper hidden_review e0da "$tmpdir/hidden-review.md"; then
  echo "helper accepted review controls hidden in an HTML comment" >&2
  exit 1
fi
grep -F 'review is missing canonical Recommendation: Approve' \
  "$tmpdir/hidden_review.output" >/dev/null

cat > "$tmpdir/fenced-review.md" <<'EOF'
```
Recommendation: Approve

Blockers:
- none

Nits:
- none
```
EOF
if run_helper fenced_review e0da "$tmpdir/fenced-review.md"; then
  echo "helper accepted review controls inside a code fence" >&2
  exit 1
fi
grep -F 'review is missing canonical Recommendation: Approve' \
  "$tmpdir/fenced_review.output" >/dev/null

cat > "$tmpdir/long-backtick-review.md" <<'EOF'
````
This four-backtick fence remains open in CommonMark.
```
Recommendation: Approve

Blockers:
- none

Nits:
- none
EOF
if run_helper long_backtick_fence e0da "$tmpdir/long-backtick-review.md"; then
  echo "helper treated a short backtick run as a long-fence closer" >&2
  exit 1
fi
grep -F 'review file contains an unclosed HTML comment or code fence' \
  "$tmpdir/long_backtick_fence.output" >/dev/null

cat > "$tmpdir/long-tilde-review.md" <<'EOF'
~~~~
This four-tilde fence remains open in CommonMark.
~~~
Recommendation: Approve

Blockers:
- none

Nits:
- none
EOF
if run_helper long_tilde_fence e0da "$tmpdir/long-tilde-review.md"; then
  echo "helper treated a short tilde run as a long-fence closer" >&2
  exit 1
fi
grep -F 'review file contains an unclosed HTML comment or code fence' \
  "$tmpdir/long_tilde_fence.output" >/dev/null

cat > "$tmpdir/longer-fence-closer-review.md" <<'EOF'
```
This example is hidden.
````
Recommendation: Approve

Blockers:
- none

Nits:
- none
EOF
run_helper longer_fence_closer e0da "$tmpdir/longer-fence-closer-review.md"
grep -Fx "$review_url" "$tmpdir/longer_fence_closer.output" >/dev/null

cat > "$tmpdir/indented-backtick-closer-review.md" <<'EOF'
````
This fence remains open because its apparent closer is indented four spaces.
    ````
Recommendation: Approve

Blockers:
- none

Nits:
- none
EOF
if run_helper indented_backtick_closer e0da "$tmpdir/indented-backtick-closer-review.md"; then
  echo "helper accepted a four-space-indented backtick closer" >&2
  exit 1
fi
grep -F 'review file contains an unclosed HTML comment or code fence' \
  "$tmpdir/indented_backtick_closer.output" >/dev/null

cat > "$tmpdir/indented-tilde-closer-review.md" <<'EOF'
~~~~
This fence remains open because its apparent closer is indented four spaces.
    ~~~~
Recommendation: Approve

Blockers:
- none

Nits:
- none
EOF
if run_helper indented_tilde_closer e0da "$tmpdir/indented-tilde-closer-review.md"; then
  echo "helper accepted a four-space-indented tilde closer" >&2
  exit 1
fi
grep -F 'review file contains an unclosed HTML comment or code fence' \
  "$tmpdir/indented_tilde_closer.output" >/dev/null

cat > "$tmpdir/comment-prefixed-indented-tilde-closer-review.md" <<'EOF'
~~~~
The apparent closer contains indented literal fenced content.
   <!-- -->~~~~
Recommendation: Approve

Blockers:
- none

Nits:
- none
EOF
if run_helper comment_prefixed_indented_tilde_closer e0da "$tmpdir/comment-prefixed-indented-tilde-closer-review.md"; then
  echo "helper accepted an indented comment-prefixed tilde closer inside a fence" >&2
  exit 1
fi
grep -F 'review file contains an unclosed HTML comment or code fence' \
  "$tmpdir/comment_prefixed_indented_tilde_closer.output" >/dev/null

cat > "$tmpdir/comment-prefixed-backtick-closer-review.md" <<'EOF'
````
The apparent closer contains literal fenced content.
<!-- -->````
Recommendation: Approve

Blockers:
- none

Nits:
- none
EOF
if run_helper comment_prefixed_backtick_closer e0da "$tmpdir/comment-prefixed-backtick-closer-review.md"; then
  echo "helper accepted a comment-prefixed backtick closer inside a fence" >&2
  exit 1
fi
grep -F 'review file contains an unclosed HTML comment or code fence' \
  "$tmpdir/comment_prefixed_backtick_closer.output" >/dev/null

awk '
  !replaced && $0 == "- none" { print "- F1 remains unresolved"; replaced=1; next }
  { print }
' "$tmpdir/review.md" > "$tmpdir/blocked-review.md"
if run_helper human_blocker e0da "$tmpdir/blocked-review.md"; then
  echo "helper accepted a human blocker" >&2
  exit 1
fi
grep -F 'review Blockers: must normalize to - none' \
  "$tmpdir/human_blocker.output" >/dev/null

cat > "$tmpdir/wrong-order-review.md" <<'EOF'
Recommendation: Approve

Nits:
- none

Blockers:
- none
EOF
if run_helper wrong_order e0da "$tmpdir/wrong-order-review.md"; then
  echo "helper accepted noncanonical review control order" >&2
  exit 1
fi
grep -F "review must use canonical \$rvw control order" \
  "$tmpdir/wrong_order.output" >/dev/null

{
  cat "$tmpdir/review.md"
  printf '\nReview narrative outside the canonical control surface.\n'
} > "$tmpdir/extra-review-prose.md"
if run_helper extra_review_prose e0da "$tmpdir/extra-review-prose.md"; then
  echo "helper accepted extra visible review prose" >&2
  exit 1
fi
grep -F "review must use canonical \$rvw control order" \
  "$tmpdir/extra_review_prose.output" >/dev/null

published_body="$(jq -r '.body' "$tmpdir/commented.review-payload.json")"
existing_review_pages="$(jq -cn \
  --arg body "$published_body" \
  --arg head "$head_sha" \
  --arg url "$review_url" \
  '[[], [{
    id: 456,
    submitted_at: "2026-09-02T22:00:00Z",
    state: "COMMENTED",
    commit_id: $head,
    user: {login: "e0da"},
    body: $body,
    html_url: $url
  }]]')"
run_helper multipage_idempotent e0da "$tmpdir/review.md" "$tmpdir/pr.json" "$existing_review_pages"
if grep -Fx POST "$tmpdir/multipage_idempotent.mutations" >/dev/null; then
  echo "helper duplicated an existing exact receipt review" >&2
  exit 1
fi
grep -Fx PATCH "$tmpdir/multipage_idempotent.mutations" >/dev/null

jq '.title = "fix: concurrently changed title"' "$tmpdir/pr.json" > "$tmpdir/concurrent-pr.json"
if run_helper concurrent_change e0da "$tmpdir/review.md" "$tmpdir/concurrent-pr.json"; then
  echo "helper overwrote a concurrent PR metadata change" >&2
  exit 1
fi
grep -F 'PR head, title, or body changed before review-link update' \
  "$tmpdir/concurrent_change.output" >/dev/null
if grep -Fx PATCH "$tmpdir/concurrent_change.mutations" >/dev/null; then
  echo "helper attempted PATCH after detecting concurrent metadata change" >&2
  exit 1
fi

if run_helper patch_failure e0da "$tmpdir/review.md" "$tmpdir/pr.json" '' true; then
  echo "helper unexpectedly hid a PATCH failure" >&2
  exit 1
fi
patch_failure_body="$(jq -r '.body' "$tmpdir/patch_failure.review-payload.json")"
patch_failure_pages="$(jq -cn \
  --arg body "$patch_failure_body" \
  --arg head "$head_sha" \
  --arg url "$review_url" \
  '[[], [{
    id: 456,
    submitted_at: "2026-09-02T22:00:00Z",
    state: "COMMENTED",
    commit_id: $head,
    user: {login: "e0da"},
    body: $body,
    html_url: $url
  }]]')"
run_helper patch_recovery e0da "$tmpdir/review.md" "$tmpdir/pr.json" "$patch_failure_pages"
if grep -Fx POST "$tmpdir/patch_recovery.mutations" >/dev/null; then
  echo "helper duplicated the review while recovering from PATCH failure" >&2
  exit 1
fi
grep -Fx PATCH "$tmpdir/patch_recovery.mutations" >/dev/null

echo "PR quality helper fixtures ok"
