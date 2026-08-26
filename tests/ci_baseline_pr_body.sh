#!/bin/sh
set -eu

fail() {
  echo "$1" >&2
  exit 1
}

workflow=".github/workflows/ci-baseline.yml"
[ -f "$workflow" ] || fail "$workflow is required"

grep -F "name: Validate current PR body" "$workflow" >/dev/null ||
  fail "$workflow must define the PR body gate"
grep -F "uses: actions/github-script@v8" "$workflow" >/dev/null ||
  fail "$workflow must use the runner-independent GitHub API client"
grep -F "github.rest.pulls.get" "$workflow" >/dev/null ||
  fail "$workflow must fetch the current PR body from the GitHub API"
grep -F "/^Refs E0D-[0-9]+\$/u" "$workflow" >/dev/null ||
  fail "$workflow must enforce one exact Linear reference"
if grep -F "github.event.pull_request.body" "$workflow" >/dev/null; then
  fail "$workflow must not trust the potentially stale event PR body"
fi

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT INT TERM
gate="$fixture_dir/pr-body-gate.js"

awk '
  $0 == "      - name: Validate current PR body" {
    in_step=1
    next
  }
  in_step && /^          script: \|$/ {
    in_script=1
    next
  }
  in_script {
    if ($0 ~ /^            /) {
      sub(/^            /, "")
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

[ -s "$gate" ] || fail "Validate current PR body script block is required"

runner="$fixture_dir/run-gate.js"
cat > "$runner" <<'EOF'
const fs = require("fs");

const gate = fs.readFileSync(process.argv[2], "utf8");
const body = fs.readFileSync(process.env.TEST_CURRENT_BODY, "utf8");
const github = {
  rest: {
    pulls: {
      get: async () => {
        if (process.env.TEST_GH_FAIL === "true") {
          throw new Error("safe fixture API failure");
        }
        return {data: {body}};
      },
    },
  },
};
const context = {repo: {owner: "e0da", repo: "actions"}, issue: {number: 123}};
const core = {
  info: (message) => process.stdout.write(`${message}\n`),
  setFailed: (message) => {
    process.stderr.write(`${message}\n`);
    process.exitCode = 1;
  },
};

const execute = new Function(
  "github",
  "context",
  "core",
  `return (async () => { ${gate}\n })();`,
);

execute(github, context, core).catch((error) => {
  process.stderr.write(`could not fetch the current PR body: ${error.message}\n`);
  process.exitCode = 1;
});
EOF
node --check "$runner"

write_body() {
  name="$1"
  content="$2"
  printf '%s' "$content" > "$fixture_dir/$name.body"
}

run_gate() {
  name="$1"
  body_path="$2"
  gh_fail="${3:-false}"

  TEST_CURRENT_BODY="$body_path" \
    TEST_GH_FAIL="$gh_fail" \
    EVENT_PR_BODY="stale event body must be ignored" \
    PR_TITLE="Refs E0D-999" \
    HEAD_REF="E0D-999" \
    node "$runner" "$gate" > "$fixture_dir/$name.out" 2>&1
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
  gh_fail="${4:-false}"
  if run_gate "$name" "$body_path" "$gh_fail"; then
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
