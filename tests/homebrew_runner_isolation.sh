#!/bin/sh
set -eu

workflow=.github/workflows/release-homebrew-interface.yml
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT HUP INT TERM

extract() {
  awk -v start="# $1:start" -v end="# $1:end" '
    index($0, start) { copying=1; next }
    index($0, end) { copying=0 }
    copying { sub(/^          /, ""); print }
  ' "$workflow" > "$fixture_dir/$1.sh"
  test -s "$fixture_dir/$1.sh"
}

extract homebrew-proof-isolation
extract homebrew-build-isolation

export RUNNER_OS=macOS RUNNER_ARCH=ARM64

if RUNNER_ENVIRONMENT=self-hosted sh "$fixture_dir/homebrew-proof-isolation.sh"; then
  echo 'fleet-host proof must fail before Homebrew is invoked' >&2
  exit 1
fi
if RUNNER_ENVIRONMENT='' sh "$fixture_dir/homebrew-proof-isolation.sh"; then
  echo 'unknown runner provenance must fail' >&2
  exit 1
fi
if RUNNER_ENVIRONMENT=github-hosted RUNNER_OS=Linux sh "$fixture_dir/homebrew-proof-isolation.sh"; then
  echo 'non-macOS installed proof must fail' >&2
  exit 1
fi
if RUNNER_ENVIRONMENT=github-hosted RUNNER_ARCH=X64 sh "$fixture_dir/homebrew-proof-isolation.sh"; then
  echo 'wrong-architecture installed proof must fail' >&2
  exit 1
fi
if RUNNER_ENVIRONMENT=github-hosted RUNNER_ARCH='' sh "$fixture_dir/homebrew-proof-isolation.sh"; then
  echo 'unknown-architecture installed proof must fail' >&2
  exit 1
fi
RUNNER_ENVIRONMENT=github-hosted sh "$fixture_dir/homebrew-proof-isolation.sh"
if RUNNER_ENVIRONMENT=self-hosted HOMEBREW_BUILD_PACKAGES=elixir sh "$fixture_dir/homebrew-build-isolation.sh"; then
  echo 'fleet-host build dependency installation must fail' >&2
  exit 1
fi
RUNNER_ENVIRONMENT=self-hosted HOMEBREW_BUILD_PACKAGES='' sh "$fixture_dir/homebrew-build-isolation.sh"
RUNNER_ENVIRONMENT=github-hosted HOMEBREW_BUILD_PACKAGES=elixir sh "$fixture_dir/homebrew-build-isolation.sh"

python3 - <<'PY'
from pathlib import Path
workflow = Path('.github/workflows/release-homebrew-interface.yml').read_text()
proof = workflow.split('  homebrew-proof:', 1)[1]
assert proof.index('name: Require isolated Homebrew runner') < proof.index('name: Validate private tap token') < proof.index('brew tap')
for name in ['environment', 'os', 'arch']:
    assert f'RUNNER_{name.upper()}: ${{{{ runner.{name} }}}}' in proof.split('name: Validate private tap token', 1)[0]
build = workflow.split('name: Install Homebrew build packages', 1)[1].split('name: Resolve destination release tag', 1)[0]
assert build.index('homebrew-build-isolation:start') < build.index('command -v brew') < build.index('brew install')
assert 'RUNNER_ENVIRONMENT: ${{ runner.environment }}' in build
PY

echo 'fleet-host Homebrew mutations rejected before tool invocation'
