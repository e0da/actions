#!/bin/sh
set -eu

fail() {
  echo "$1" >&2
  exit 1
}

workflow=".github/workflows/ci-baseline.yml"
[ -f "$workflow" ] || fail "$workflow is required"

require_literal() {
  literal="$1"
  grep -F "$literal" "$workflow" >/dev/null ||
    fail "$workflow missing literal: $literal"
}

require_literal "name: Validate current PR body"
require_literal "uses: actions/github-script@v8"
require_literal "github.rest.pulls.get"
require_literal 'const normalizedBody = (pullRequest.body ?? "").replace(/\s+$/u, "");'
require_literal '/^Refs E0D-[0-9]+$/u.test(normalizedBody)'
require_literal "PR body validation could not fetch the current PR body."
require_literal "PR body must be exactly 'Refs E0D-<number>' (trailing whitespace is ignored)."

if grep -F "github.event.pull_request.body" "$workflow" >/dev/null; then
  fail "$workflow must not trust the potentially stale event PR body"
fi
if grep -F "core.info(normalizedBody" "$workflow" >/dev/null ||
  grep -F "console.log" "$workflow" >/dev/null ||
  grep -F "core.setOutput" "$workflow" >/dev/null; then
  fail "$workflow must not emit the current PR body"
fi

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT INT TERM

write_body() {
  name="$1"
  content="$2"
  printf '%s' "$content" > "$fixture_dir/$name.body"
}

validate_current_body() {
  if [ "${TEST_API_FAIL:-false}" = "true" ]; then
    echo "PR body validation could not fetch the current PR body." >&2
    return 1
  fi

  normalized_body="$(cat "$TEST_CURRENT_BODY")"
  while :; do
    case "$normalized_body" in
      *[[:space:]]) normalized_body="${normalized_body%?}" ;;
      *) break ;;
    esac
  done

  case "$normalized_body" in
    *'
'*)
      echo "PR body must be exactly 'Refs E0D-<number>' (trailing whitespace is ignored)." >&2
      return 1
      ;;
  esac

  if ! printf '%s' "$normalized_body" | grep -Eq '^Refs E0D-[0-9]+$'; then
    echo "PR body must be exactly 'Refs E0D-<number>' (trailing whitespace is ignored)." >&2
    return 1
  fi

  echo "PR body contains one exact Linear issue reference."
}

run_gate() {
  name="$1"
  body_path="$2"
  api_fail="${3:-false}"

  TEST_CURRENT_BODY="$body_path" \
    TEST_API_FAIL="$api_fail" \
    EVENT_PR_BODY="stale event body must be ignored" \
    PR_TITLE="Refs E0D-999" \
    HEAD_REF="E0D-999" \
    validate_current_body > "$fixture_dir/$name.out" 2>&1
}

expect_success() {
  name="$1"
  body_path="$2"
  run_gate "$name" "$body_path" || fail "expected success: $name"
}

expect_failure() {
  name="$1"
  body_path="$2"
  expected="$3"
  api_fail="${4:-false}"
  if run_gate "$name" "$body_path" "$api_fail"; then
    fail "expected failure: $name"
  fi
  grep -F "$expected" "$fixture_dir/$name.out" >/dev/null ||
    fail "$name did not report the expected safe error"
}

write_body exact "Refs E0D-1576"
expect_success exact "$fixture_dir/exact.body"

printf 'Refs E0D-1576 \t\n\n' > "$fixture_dir/trailing-whitespace.body"
expect_success trailing_whitespace "$fixture_dir/trailing-whitespace.body"

: > "$fixture_dir/empty.body"
expect_failure empty "$fixture_dir/empty.body" "PR body must be exactly"

write_body malformed "E0D-1576"
expect_failure malformed "$fixture_dir/malformed.body" "PR body must be exactly"

write_body multiple "Refs E0D-1576 Refs E0D-1577"
expect_failure multiple "$fixture_dir/multiple.body" "PR body must be exactly"

printf 'Refs E0D-1576\nRefs E0D-1577' > "$fixture_dir/multiple-lines.body"
expect_failure multiple_lines "$fixture_dir/multiple-lines.body" "PR body must be exactly"

write_body closing "Fixes E0D-1576"
expect_failure closing_word "$fixture_dir/closing.body" "PR body must be exactly"

write_body leading " Refs E0D-1576"
expect_failure leading_whitespace "$fixture_dir/leading.body" "PR body must be exactly"

expect_failure branch_title_only "$fixture_dir/empty.body" "PR body must be exactly"

write_body arbitrary "PRIVATE BODY CONTENT MUST NOT BE ECHOED"
expect_failure body_not_echoed "$fixture_dir/arbitrary.body" "PR body must be exactly"
if grep -F "PRIVATE BODY CONTENT MUST NOT BE ECHOED" "$fixture_dir/body_not_echoed.out" >/dev/null; then
  fail "gate output exposed the arbitrary PR body"
fi

write_body stale_event_current_valid "Refs E0D-1576"
expect_success stale_event_current_valid "$fixture_dir/stale_event_current_valid.body"

write_body stale_event_current_invalid "current API body is invalid"
expect_failure stale_event_current_invalid "$fixture_dir/stale_event_current_invalid.body" "PR body must be exactly"

write_body recoverable "not ready"
expect_failure recoverable_before_edit "$fixture_dir/recoverable.body" "PR body must be exactly"
write_body recoverable "Refs E0D-1576"
expect_success recoverable_after_edit "$fixture_dir/recoverable.body"

expect_failure api_failure "$fixture_dir/exact.body" "could not fetch the current PR body" true

echo "ci baseline PR body fixtures ok"
