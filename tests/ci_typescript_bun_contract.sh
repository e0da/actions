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
require_literal "      system-deps:"
require_literal '        description: "Optional space-delimited Debian package names installed before dependencies and checks."'
require_literal "      - name: Install system dependencies"
require_literal "      - name: Check formatting"
require_literal "      - name: Lint"
require_literal "      - name: Build"
require_literal "      - name: Type check"
require_literal "        if: \${{ inputs.playwright-browser != '' }}"
require_literal "          bunx playwright install \"\$PLAYWRIGHT_BROWSER\""

reject_literal "Install ripgrep"
reject_literal "--with-deps"
reject_pattern '(^|[[:space:]])rg([[:space:]]|$)'

system_deps_line="$(grep -nF '      - name: Install system dependencies' "$workflow" | cut -d: -f1)"
install_dependencies_line="$(grep -nF '      - name: Install dependencies' "$workflow" | cut -d: -f1)"
[ "$system_deps_line" -lt "$install_dependencies_line" ] ||
  fail "system dependencies must install before Bun dependencies and checks"

mock_bin="$tmpdir/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/apt-get" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$APT_CALLS"
SH
chmod +x "$mock_bin/apt-get"

cat >"$mock_bin/id" <<'SH'
#!/bin/sh
set -eu
[ "${1-}" = "-u" ] || exit 2
printf '%s\n' "$ID_UID"
SH
chmod +x "$mock_bin/id"

cat >"$mock_bin/sudo" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$SUDO_CALLS"
SH
chmod +x "$mock_bin/sudo"

system_deps_step="$tmpdir/system-deps-step.sh"
extract_run_step "Install system dependencies" "$system_deps_step"

SUDO_CALLS="$tmpdir/empty-system-deps.calls" \
  APT_CALLS="$tmpdir/empty-system-deps.apt-calls" \
  ID_UID=1000 \
  SYSTEM_DEPS='' \
  PATH="$mock_bin:$PATH" \
  bash "$system_deps_step"
[ ! -e "$tmpdir/empty-system-deps.calls" ] ||
  fail "empty system-deps must not invoke apt"

SUDO_CALLS="$tmpdir/redis-system-deps.calls" \
  APT_CALLS="$tmpdir/redis-system-deps.apt-calls" \
  ID_UID=1000 \
  SYSTEM_DEPS='redis-server ca-certificates' \
  PATH="$mock_bin:$PATH" \
  bash "$system_deps_step"
grep -Fx "apt-get update -q" "$tmpdir/redis-system-deps.calls" >/dev/null ||
  fail "system-deps did not update apt metadata"
grep -Fx "apt-get install -y --no-install-recommends -- redis-server ca-certificates" "$tmpdir/redis-system-deps.calls" >/dev/null ||
  fail "system-deps were not forwarded as validated package arguments"

SUDO_CALLS="$tmpdir/root-system-deps.sudo-calls" \
  APT_CALLS="$tmpdir/root-system-deps.apt-calls" \
  ID_UID=0 \
  SYSTEM_DEPS='redis-server' \
  PATH="$mock_bin:$PATH" \
  bash "$system_deps_step"
[ ! -e "$tmpdir/root-system-deps.sudo-calls" ] ||
  fail "root runners must not require sudo"
grep -Fx "update -q" "$tmpdir/root-system-deps.apt-calls" >/dev/null ||
  fail "root runner did not update apt metadata directly"
grep -Fx "install -y --no-install-recommends -- redis-server" "$tmpdir/root-system-deps.apt-calls" >/dev/null ||
  fail "root runner did not install system-deps directly"

if SUDO_CALLS="$tmpdir/invalid-system-deps.calls" \
  APT_CALLS="$tmpdir/invalid-system-deps.apt-calls" \
  ID_UID=1000 \
  SYSTEM_DEPS='redis-server;touch-pwned' \
  PATH="$mock_bin:$PATH" \
  bash "$system_deps_step"; then
  fail "unsafe system-deps input must fail"
fi
[ ! -e "$tmpdir/invalid-system-deps.calls" ] ||
  fail "unsafe system-deps input must fail before invoking apt"

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
