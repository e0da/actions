#!/bin/sh
set -eu

workflow=.github/workflows/ci-node-npm.yml

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

require_literal "name: CI Node (npm)"
require_literal "  workflow_call:"
require_literal "      runner:"
require_literal "      node-version:"
require_literal "      test-command:"
require_literal "    runs-on: \${{ inputs.runner }}"
require_literal "      - uses: actions/setup-node@"
require_literal "      - name: Install from lockfile"
require_literal "        run: npm ci"
require_literal "      - name: Build"
require_literal "      - name: Test"

# npm ci is the whole point: it is the only install path that consumes
# package-lock.json, which is the single file a lockfile-only dependency bump
# changes. An install that resolves from package.json ranges instead would go
# green without ever reading the bump.
reject_literal "npm install" "npm ci is the install contract; npm install rewrites the lockfile"
reject_literal "bun install" "npm repos must install with npm, not bun"

# The test step must stay opt-in. Repos in this family ship placeholder test
# scripts (`echo "Error: no test specified" && exit 1`). Auto-running `npm test`
# when a test script merely exists would fail CI without proving anything.
if grep -E '^ *run: npm test' "$workflow" >/dev/null; then
  echo "test step must not run npm test unconditionally" >&2
  exit 1
fi

require_literal "          TEST_COMMAND: "
if ! grep -F 'TEST_COMMAND" ]]; then' "$workflow" >/dev/null; then
  echo "test step must be gated on an explicit test-command input" >&2
  exit 1
fi

# The build step must be conditional. Not every npm repo has a build script,
# and `npm run build` on a repo without one exits non-zero.
if ! grep -F "scripts?.build" "$workflow" >/dev/null; then
  echo "build step must detect package.json scripts.build before running" >&2
  exit 1
fi

echo "ci-node-npm contract fixture ok"
