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

workflow=".github/workflows/release-elixir.yml"
[ -f "$workflow" ] || fail "$workflow is required"

require_literal "$workflow" "name: Release Elixir"
require_literal "$workflow" "  workflow_call:"
require_literal "$workflow" "      app-name:"
require_literal "$workflow" "      image-name:"
require_literal "$workflow" "      validate-runner:"
require_literal "$workflow" "      image-runner:"
require_literal "$workflow" "      publish-runner:"
require_literal "$workflow" "      otp-version:"
require_literal "$workflow" "      elixir-version:"
require_literal "$workflow" "      beam-mode:"
require_literal "$workflow" "      deps-command:"
require_literal "$workflow" "      version-command:"
require_literal "$workflow" "      tag-prefix:"
require_literal "$workflow" "      docker-context:"
require_literal "$workflow" "      dockerfile:"
require_literal "$workflow" "      platforms:"
require_literal "$workflow" "      build-args:"
require_literal "$workflow" "      target:"
require_literal "$workflow" "      push-image:"
require_literal "$workflow" "      push-latest:"
require_literal "$workflow" "      extra-tags:"
require_literal "$workflow" "      publish-github-release:"
require_literal "$workflow" "      private_deps_ssh_key:"
require_literal "$workflow" "      GHCR_TOKEN:"
require_literal "$workflow" '      version:'
require_literal "$workflow" '      prerelease:'
require_literal "$workflow" '      image:'
require_literal "$workflow" '      image-tags:'
require_literal "$workflow" '      image-digest:'

require_literal "$workflow" "case \"\$BEAM_MODE\" in"
require_literal "$workflow" "Code.require_file(\\\"mix.exs\\\")"
require_literal "$workflow" "version_output=\"\$RUNNER_TEMP/elixir-release-version.txt\""
require_literal "$workflow" "version-command failed"
require_literal "$workflow" "expected_tag=\"\${TAG_PREFIX}\${version}\""
require_literal "$workflow" "PRERELEASE: \${{ steps.release-meta.outputs.prerelease }}"
require_literal "$workflow" "if [ \"\$PUSH_LATEST\" = \"true\" ] && [ \"\$PRERELEASE\" = \"false\" ]; then"
require_literal "$workflow" "docker/login-action@v4"
require_literal "$workflow" "docker/setup-qemu-action@v4"
require_literal "$workflow" "docker/setup-buildx-action@v4"
require_literal "$workflow" "docker/build-push-action@v7"
require_literal "$workflow" "platforms: \${{ inputs.platforms }}"
require_literal "$workflow" "tags: \${{ needs.validate.outputs.image-tags }}"
require_literal "$workflow" "image-digest=\${{ steps.build.outputs.digest }}"
require_literal "$workflow" "softprops/action-gh-release@v3"

reject_literal "$workflow" "shell: bash"
reject_literal "$workflow" "python3"

echo "release elixir workflow contract ok"
