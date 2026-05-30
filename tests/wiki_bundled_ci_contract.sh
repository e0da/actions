#!/bin/sh
set -eu

workflow=.github/workflows/ci-wiki-bundled.yml

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

require_literal "name: Reusable Wiki CI"
require_literal "  workflow_call:"
require_literal "      runner:"
require_literal "      runner-profile:"
require_literal "      runner-capabilities:"
require_literal "      runner-manifest:"
require_literal "      tool-mode:"
require_literal "      link-args:"
require_literal "      ruby-version:"
require_literal "      build-command:"
require_literal "      test-command:"
require_literal "      hosted-drift-mode:"
require_literal "      hosted-drift-allowlist-path:"
require_literal "      approval-labels:"
require_literal "      approval-report:"
require_literal "  wiki-ci:"
require_literal "    name: Wiki CI"
require_literal "    runs-on: \${{ inputs.runner }}"
require_literal "      - name: Validate runner contract"
require_literal "      - name: Approval report"
require_literal "      - name: Check PR title"
require_literal "      - name: Scan workflow runner routing"
require_literal "      - name: Secret scan"
require_literal "        continue-on-error: true"
require_literal "      - name: Check links"
require_literal "      - name: Validate YAML frontmatter in .md files"
require_literal "      - name: Build"
require_literal "      - name: Test"
require_literal "      - name: Write check summary"
require_literal "GITHUB_STEP_SUMMARY"

echo "wiki bundled CI contract fixture ok"
