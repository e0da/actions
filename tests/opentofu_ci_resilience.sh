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

reject_exact_line() {
  file="$1"
  line="$2"

  if awk -v expected="$line" '$0 == expected { found = 1 } END { exit found ? 0 : 1 }' "$file"; then
    fail "$file should not contain exact line: $line"
  fi
}

workflow=".github/workflows/ci-opentofu.yml"
readme="README.md"

require_literal "$workflow" "      provider-cache-mode:"
require_literal "$workflow" "      provider-download-retry:"
require_literal "$workflow" "      registry-discovery-retry:"
require_literal "$workflow" "      registry-client-timeout:"
require_literal "$workflow" "      - name: Prepare OpenTofu provider cache"
require_literal "$workflow" "TF_PLUGIN_CACHE_DIR: \${{ github.workspace }}/.opentofu/plugin-cache"
require_literal "$workflow" "mkdir -p \"\$TF_PLUGIN_CACHE_DIR\""
require_literal "$workflow" "printf 'TF_PLUGIN_CACHE_DIR=%s\\n' \"\$TF_PLUGIN_CACHE_DIR\" >> \"\$GITHUB_ENV\""
require_literal "$workflow" "      - name: Cache OpenTofu providers"
require_literal "$workflow" "uses: actions/cache@v5"
require_literal "$workflow" "if: inputs.provider-cache-mode == 'read-write'"
require_literal "$workflow" "path: \${{ github.workspace }}/.opentofu/plugin-cache"
require_literal "$workflow" "opentofu-provider-\${{ runner.os }}-\${{ runner.arch }}-\${{ inputs.tofu-version }}-\${{ hashFiles('**/.terraform.lock.hcl') }}"
require_literal "$workflow" "TF_PROVIDER_DOWNLOAD_RETRY: \${{ inputs.provider-download-retry }}"
require_literal "$workflow" "TF_REGISTRY_DISCOVERY_RETRY: \${{ inputs.registry-discovery-retry }}"
require_literal "$workflow" "TF_REGISTRY_CLIENT_TIMEOUT: \${{ inputs.registry-client-timeout }}"
require_literal "$workflow" "sh -c \"\$VALIDATE_COMMAND\""
reject_exact_line "$workflow" "      TF_PLUGIN_CACHE_DIR: \${{ github.workspace }}/.opentofu/plugin-cache"
reject_literal "$workflow" "bash -lc \"\$VALIDATE_COMMAND\""

require_literal "$readme" "provider-cache-mode"
require_literal "$readme" "provider-download-retry"
require_literal "$readme" "registry-discovery-retry"
require_literal "$readme" "registry-client-timeout"

echo "opentofu ci resilience ok"
