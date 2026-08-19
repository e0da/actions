#!/bin/sh
set -eu

workflow=.github/workflows/ci-typescript-bun.yml
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

fail() {
  echo "ci-typescript-bun contract: $*" >&2
  exit 1
}

require_literal() {
  literal="$1"
  grep -F -- "$literal" "$workflow" >/dev/null || fail "missing literal: $literal"
}

reject_literal() {
  literal="$1"
  if grep -F -- "$literal" "$workflow" >/dev/null; then
    fail "forbidden literal: $literal"
  fi
}

reject_pattern() {
  pattern="$1"
  if grep -E "$pattern" "$workflow" >/dev/null; then
    fail "forbidden pattern: $pattern"
  fi
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
  bash -n "$destination"
}

require_literal "      format-command:"
require_literal "      lint-command:"
require_literal "      build-command:"
require_literal "      check-command:"
require_literal "      test-command:"
require_literal "      playwright-browser:"
require_literal "      - name: Check formatting"
require_literal "      - name: Lint"
require_literal "      - name: Build"
require_literal "      - name: Type check"
require_literal "        if: \${{ inputs.playwright-browser != '' }}"
require_literal "          bunx playwright install \"\$PLAYWRIGHT_BROWSER\""

reject_literal "Install ripgrep"
reject_literal "apt-get"
reject_literal "--with-deps"
reject_pattern '(^|[[:space:]])rg([[:space:]]|$)'

mock_bin="$tmpdir/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/bun" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$BUN_CALLS"

if [ "${1-}" = "-e" ]; then
  case "${2-}" in
    *'"format:check"'*) exit 1 ;;
    *'"lint"'* | *'"build"'* | *'"check"'*) exit 0 ;;
    *) exit 1 ;;
  esac
fi
SH
chmod +x "$mock_bin/bun"

cat >"$mock_bin/bunx" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$BUNX_CALLS"
SH
chmod +x "$mock_bin/bunx"

gameboard_calls="$tmpdir/gameboard-defaults.calls"
for command_step in "Check formatting" Lint Build "Type check"; do
  extracted_step="$tmpdir/${command_step}-step.sh"
  extract_run_step "$command_step" "$extracted_step"

  case "$command_step" in
    "Check formatting") command_env=FORMAT_COMMAND; command_key=format ;;
    Lint) command_env=LINT_COMMAND; command_key=lint ;;
    Build) command_env=BUILD_COMMAND; command_key=build ;;
    "Type check") command_env=CHECK_COMMAND; command_key=check ;;
  esac

  BUN_CALLS="$gameboard_calls" \
    PATH="$mock_bin:$PATH" \
    env "$command_env=" bash "$extracted_step"

  override_output="$tmpdir/$command_key.override.out"
  override_bun_calls="$tmpdir/$command_key.override.bun-calls"
  BUN_CALLS="$override_bun_calls" \
    PATH="$mock_bin:$PATH" \
    env "$command_env=printf '%s\\n' $command_key-override >'$override_output'" \
    bash "$extracted_step"
  grep -Fx "$command_key-override" "$override_output" >/dev/null ||
    fail "$command_env did not replace the package-script default"
  if [ -e "$override_bun_calls" ]; then
    fail "$command_env must bypass package-script detection"
  fi
done

if grep -Fx "run format:check" "$gameboard_calls" >/dev/null; then
  fail "a missing format:check script must not fail an existing caller"
fi
for expected_call in "run lint" "run build" "run check"; do
  grep -Fx "$expected_call" "$gameboard_calls" >/dev/null ||
    fail "Gameboard-compatible defaults missing: $expected_call"
done

test_step="$tmpdir/test-step.sh"
extract_run_step "Test" "$test_step"

BUN_CALLS="$tmpdir/default-test.calls" \
  TEST_COMMAND='' \
  PATH="$mock_bin:$PATH" \
  bash "$test_step"
grep -Fx "test" "$tmpdir/default-test.calls" >/dev/null ||
  fail "empty test-command must run bun test"

BUN_CALLS="$tmpdir/override-test.bun-calls" \
  TEST_COMMAND="printf '%s\\n' override-ran >'$tmpdir/override-test.out'" \
  PATH="$mock_bin:$PATH" \
  bash "$test_step"
grep -Fx "override-ran" "$tmpdir/override-test.out" >/dev/null ||
  fail "explicit test-command was not executed"
if [ -e "$tmpdir/override-test.bun-calls" ]; then
  fail "explicit test-command must replace bun test"
fi

playwright_step="$tmpdir/playwright-step.sh"
extract_run_step "Install Playwright browser" "$playwright_step"

BUNX_CALLS="$tmpdir/playwright.calls" \
  PLAYWRIGHT_BROWSER=chromium \
  PATH="$mock_bin:$PATH" \
  bash "$playwright_step"
grep -Fx "playwright install chromium" "$tmpdir/playwright.calls" >/dev/null ||
  fail "Playwright browser input was not forwarded as one argument"

if BUNX_CALLS="$tmpdir/playwright-option.calls" \
  PLAYWRIGHT_BROWSER=--with-deps \
  PATH="$mock_bin:$PATH" \
  bash "$playwright_step"; then
  fail "Playwright option injection must fail"
fi
if [ -e "$tmpdir/playwright-option.calls" ]; then
  fail "invalid Playwright input must fail before invoking bunx"
fi

echo "ci-typescript-bun contract fixture ok"
