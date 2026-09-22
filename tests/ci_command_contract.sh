#!/bin/sh
set -eu

workflow=.github/workflows/ci-command.yml
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

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

reject_literal() {
  rejected="$1"
  reason="$2"
  if grep -F "$rejected" "$workflow" >/dev/null; then
    echo "forbidden workflow text: $rejected ($reason)" >&2
    exit 1
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

  [ -s "$destination" ] || {
    echo "could not extract workflow step: $step_name" >&2
    exit 1
  }
  bash -n "$destination"
}

require_literal "name: CI Command"
require_literal "  workflow_call:"
require_literal "      runner:"
require_literal "      command:"
require_literal "      working-directory:"
require_literal "      system-deps:"
require_literal "      dotnet-version:"
require_literal "      python-version:"
require_literal "    runs-on: \${{ inputs.runner }}"
require_literal "      - name: Configure .NET install directory"
require_literal "          DOTNET_INSTALL_DIR: \${{ runner.temp }}/dotnet"
require_literal "        run: printf '%s\n' \"DOTNET_INSTALL_DIR=\$DOTNET_INSTALL_DIR\" >> \"\$GITHUB_ENV\""
require_literal "        if: inputs.dotnet-version != ''"
require_literal "        uses: actions/setup-dotnet@v5"
require_literal "          dotnet-version: \${{ inputs.dotnet-version }}"
require_literal "        if: inputs.python-version != ''"
require_literal "        uses: actions/setup-python@v6"
require_literal "          python-version: \${{ inputs.python-version }}"
require_literal "          CALLER_COMMAND: \${{ inputs.command }}"
require_literal "        run: bash -lc \"\$CALLER_COMMAND\""

require_literal "      - name: Install system dependencies"
require_literal "          SYSTEM_DEPS: \${{ inputs.system-deps }}"

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

SUDO_CALLS="$tmpdir/system-deps.calls" \
  APT_CALLS="$tmpdir/system-deps.apt-calls" \
  ID_UID=1000 \
  SYSTEM_DEPS='cmake build-essential ninja-build' \
  PATH="$mock_bin:$PATH" \
  bash "$system_deps_step"
grep -Fx "apt-get update -q" "$tmpdir/system-deps.calls" >/dev/null || {
  echo "system-deps did not update apt metadata" >&2
  exit 1
}
grep -Fx "apt-get install -y --no-install-recommends -- cmake build-essential ninja-build" "$tmpdir/system-deps.calls" >/dev/null || {
  echo "system-deps were not forwarded as validated package arguments" >&2
  exit 1
}

if SUDO_CALLS="$tmpdir/invalid-system-deps.calls" \
  APT_CALLS="$tmpdir/invalid-system-deps.apt-calls" \
  ID_UID=1000 \
  SYSTEM_DEPS='cmake;touch-pwned' \
  PATH="$mock_bin:$PATH" \
  bash "$system_deps_step"; then
  echo "unsafe system-deps input must fail" >&2
  exit 1
fi
[ ! -e "$tmpdir/invalid-system-deps.calls" ] || {
  echo "unsafe system-deps input must fail before invoking apt" >&2
  exit 1
}

# GITHUB_ENV preserves the runner-writable path for setup-dotnet and the caller.
dotnet_install_dir_count="$(grep -Fxc "          DOTNET_INSTALL_DIR: \${{ runner.temp }}/dotnet" "$workflow")"
if [ "$dotnet_install_dir_count" -ne 1 ]; then
  echo "DOTNET_INSTALL_DIR must be set exactly once for the configuration step" >&2
  exit 1
fi

# The shared contract orchestrates setup and execution. Product-specific build
# commands remain in each caller repository.
reject_literal "KspContinuum" "shared workflows must not embed KSP product commands"
reject_literal "dotnet run" "the caller owns its .NET build and test command"
reject_literal "python -m unittest" "the caller owns its Python test command"
reject_literal "cmake --build" "the caller owns its native build command"

echo "ci-command contract fixture ok"
