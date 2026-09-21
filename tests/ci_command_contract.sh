#!/bin/sh
set -eu

workflow=.github/workflows/ci-command.yml

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

require_literal "name: CI Command"
require_literal "  workflow_call:"
require_literal "      runner:"
require_literal "      command:"
require_literal "      working-directory:"
require_literal "      dotnet-version:"
require_literal "      python-version:"
require_literal "    runs-on: \${{ inputs.runner }}"
require_literal "        if: inputs.dotnet-version != ''"
require_literal "        uses: actions/setup-dotnet@v5"
require_literal "          dotnet-version: \${{ inputs.dotnet-version }}"
require_literal "        if: inputs.python-version != ''"
require_literal "        uses: actions/setup-python@v6"
require_literal "          python-version: \${{ inputs.python-version }}"
require_literal "          CALLER_COMMAND: \${{ inputs.command }}"
require_literal "        run: bash -lc \"\$CALLER_COMMAND\""

# The shared contract orchestrates setup and execution. Product-specific build
# commands remain in each caller repository.
reject_literal "KspContinuum" "shared workflows must not embed KSP product commands"
reject_literal "dotnet run" "the caller owns its .NET build and test command"
reject_literal "python -m unittest" "the caller owns its Python test command"
reject_literal "cmake --build" "the caller owns its native build command"

echo "ci-command contract fixture ok"
