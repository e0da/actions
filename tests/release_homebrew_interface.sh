#!/bin/sh
set -eu

fail() {
  echo "$1" >&2
  exit 1
}

require_literal() {
  file="$1"
  literal="$2"

  grep -F "$literal" "$file" >/dev/null || fail "$file missing literal: $literal"
}

reject_literal() {
  file="$1"
  literal="$2"

  if grep -F "$literal" "$file" >/dev/null; then
    fail "$file should not contain literal: $literal"
  fi
}

workflow=".github/workflows/release-homebrew-interface.yml"
[ -f "$workflow" ] || fail "$workflow is required"

require_literal "$workflow" "name: Release Homebrew Interface"
require_literal "$workflow" "  workflow_call:"
require_literal "$workflow" "      release-interface:"
require_literal "$workflow" "      build-output-dir:"
require_literal "$workflow" "      built-binary-name:"
require_literal "$workflow" "      artifact-name:"
require_literal "$workflow" "      setup-bun:"
require_literal "$workflow" "      bun-version:"
require_literal "$workflow" "      bun-install-command:"
require_literal "$workflow" "      release-env:"
require_literal "$workflow" "      homebrew-build-packages:"
require_literal "$workflow" "      publish-runner:"
require_literal "$workflow" "      homebrew-tap:"
require_literal "$workflow" "      homebrew-formula:"
require_literal "$workflow" "      publish-github-release:"
require_literal "$workflow" "      run-homebrew-proof:"
require_literal "$workflow" "      installed-smoke-command:"
require_literal "$workflow" "sh \"\$RELEASE_INTERFACE\" metadata"
require_literal "$workflow" "oven-sh/setup-bun@v2"
require_literal "$workflow" "if: inputs.setup-bun"
require_literal "$workflow" "if: inputs.setup-bun && inputs.bun-install-command != ''"
require_literal "$workflow" "\${{ inputs.bun-install-command }}"
require_literal "$workflow" "RELEASE_ENV: \${{ inputs.release-env }}"
require_literal "$workflow" "invalid release-env key:"
require_literal "$workflow" "printf '%s\\n' \"\$line\" >> \"\$GITHUB_ENV\""
require_literal "$workflow" "HOMEBREW_BUILD_PACKAGES: \${{ inputs.homebrew-build-packages }}"
require_literal "$workflow" "brew install \"\$package\""
require_literal "$workflow" "sh \"\$RELEASE_INTERFACE\" test"
require_literal "$workflow" "sh \"\$RELEASE_INTERFACE\" build \"\$BUILD_OUTPUT_DIR\""
require_literal "$workflow" "SMOKE_BINARY_NAME=\"\$HOMEBREW_FORMULA\""
require_literal "$workflow" "sh \"\$RELEASE_INTERFACE\" smoke \"\$BUILD_OUTPUT_DIR/bin/\$SMOKE_BINARY_NAME\""
require_literal "$workflow" "safe_ref=\$(printf '%s' \"\$GITHUB_REF_NAME\" | tr '/:@ ' '----')"
require_literal "$workflow" "tar -C \"\$BUILD_OUTPUT_DIR\" -czf \"\$archive\" ."
require_literal "$workflow" "shasum -a 256 \"\$archive\" > \"\$archive.sha256\""
require_literal "$workflow" "if: inputs.publish-github-release && github.ref_type != 'tag'"
require_literal "$workflow" "if: inputs.publish-github-release && github.ref_type == 'tag'"
require_literal "$workflow" "contents: read"
require_literal "$workflow" "contents: write"
require_literal "$workflow" "GH_REPO: \${{ github.repository }}"
require_literal "$workflow" "gh release create \"\$GITHUB_REF_NAME\""
require_literal "$workflow" "CALLER_HOMEBREW_GITHUB_API_TOKEN:"
require_literal "$workflow" "HOMEBREW_GITHUB_API_TOKEN secret is required for e0da/internal Homebrew proof."
require_literal "$workflow" "brew tap \"\$HOMEBREW_TAP\""
require_literal "$workflow" "brew fetch --force \"\$HOMEBREW_TAP/\$HOMEBREW_FORMULA\""
require_literal "$workflow" "brew install \"\$HOMEBREW_TAP/\$HOMEBREW_FORMULA\""
require_literal "$workflow" "brew uninstall --force \"\$HOMEBREW_TAP/\$HOMEBREW_FORMULA\""
require_literal "$workflow" "brew test \"\$HOMEBREW_TAP/\$HOMEBREW_FORMULA\""

reject_literal "$workflow" "shell: bash"
reject_literal "$workflow" "python3"
reject_literal "$workflow" "ruby "

echo "release homebrew interface workflow ok"
