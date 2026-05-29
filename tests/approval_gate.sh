#!/bin/sh
set -eu

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

gate="$tmpdir/approval-gate.sh"
awk '
  /^      - name: Evaluate approval gate$/ {
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
' .github/workflows/approval-gate.yml > "$gate"
sh -n "$gate"

mock_bin="$tmpdir/bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/gh" <<'SH'
#!/bin/sh
set -eu

if [ "$1" != "api" ]; then
  echo "unexpected gh command: $*" >&2
  exit 1
fi

case "$2" in
  repos/e0da/actions/issues/123/labels)
    cat "$TEST_LABELS"
    ;;
  repos/e0da/actions/pulls/123/reviews)
    cat "$TEST_REVIEWS"
    ;;
  *)
    echo "unexpected gh api path: $2" >&2
    exit 1
    ;;
esac
SH
chmod +x "$mock_bin/gh"

write_lines() {
  path="$1"
  shift
  : > "$path"
  for line in "$@"; do
    printf '%s\n' "$line" >> "$path"
  done
}

run_gate() {
  name="$1"
  labels="$2"
  reviews="$3"
  allowed="$4"
  pr_number="$5"
  require_pr="$6"

  labels_file="$tmpdir/${name}.labels"
  reviews_file="$tmpdir/${name}.reviews"
  summary_file="$tmpdir/${name}.summary"
  output_file="$tmpdir/${name}.out"
  write_lines "$labels_file" "$labels"
  write_lines "$reviews_file" "$reviews"

  (
    PATH="$mock_bin:$PATH" \
      RUNNER_TEMP="$tmpdir/${name}.runner" \
      GITHUB_STEP_SUMMARY="$summary_file" \
      GH_TOKEN=fake-token \
      REPOSITORY=e0da/actions \
      PULL_REQUEST_NUMBER="$pr_number" \
      ALLOWED_LABELS="$allowed" \
      REQUIRE_PR_EVENT="$require_pr" \
      REPORT_MODE=summary \
      TEST_LABELS="$labels_file" \
      TEST_REVIEWS="$reviews_file" \
      sh "$gate"
  ) > "$output_file" 2>&1
}

expect_success() {
  name="$1"
  shift
  run_gate "$name" "$@"
}

expect_failure() {
  name="$1"
  expected="$2"
  shift 2
  if run_gate "$name" "$@"; then
    echo "expected failure: $name" >&2
    exit 1
  fi
  grep -F "$expected" "$tmpdir/${name}.out" >/dev/null
}

expect_success \
  approved_review \
  "" \
  "$(printf 'reviewer\tAPPROVED')" \
  "approved[agency]" \
  123 \
  true
grep -F "Approved review signal: reviewer" "$tmpdir/approved_review.out" >/dev/null

expect_success \
  allowed_label \
  "approved[agency]" \
  "" \
  "approved[agency]" \
  123 \
  true
grep -F "Approved label signal: approved[agency]" "$tmpdir/allowed_label.out" >/dev/null

expect_success \
  comma_allowed_label \
  "approved[e0da]" \
  "" \
  "approved[agency], approved[e0da]" \
  123 \
  true

expect_failure \
  unallowed_approval_label \
  "approval gate failed" \
  "approved[other]" \
  "" \
  "approved[agency]" \
  123 \
  true
grep -F "Ignored approval labels: approved[other]" "$tmpdir/unallowed_approval_label.out" >/dev/null

expect_failure \
  ordinary_label_only \
  "approval gate failed" \
  "needs-review" \
  "" \
  "approved[agency]" \
  123 \
  true

expect_failure \
  comment_text_absent_from_api \
  "approval gate failed" \
  "" \
  "" \
  "approved[agency]" \
  123 \
  true

expect_failure \
  invalid_allowed_label \
  "must match approved[<approver-id>]" \
  "" \
  "" \
  "approved agency" \
  123 \
  true

expect_failure \
  missing_pr_required \
  "approval gate requires pull request context" \
  "" \
  "" \
  "approved[agency]" \
  "" \
  true

expect_success \
  missing_pr_not_required \
  "" \
  "" \
  "approved[agency]" \
  "" \
  false
grep -F "Approval gate skipped outside pull request context." "$tmpdir/missing_pr_not_required.out" >/dev/null

echo "approval gate fixtures ok"
