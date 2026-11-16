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
import re
workflow = Path('.github/workflows/release-homebrew-interface.yml').read_text()
proof = workflow.split('  homebrew-proof:', 1)[1]
assert proof.index('name: Require isolated Homebrew runner') < proof.index('name: Validate private tap token') < proof.index('name: Configure private tap Git authentication') < proof.index('brew tap')
for name in ['environment', 'os', 'arch']:
    assert f'RUNNER_{name.upper()}: ${{{{ runner.{name} }}}}' in proof.split('name: Validate private tap token', 1)[0]
build = workflow.split('name: Install Homebrew build packages', 1)[1].split('name: Resolve destination release tag', 1)[0]
assert build.index('homebrew-build-isolation:start') < build.index('command -v brew') < build.index('brew install')
assert 'RUNNER_ENVIRONMENT: ${{ runner.environment }}' in build

condition = re.search(r"^    if: (.+)$", proof, re.MULTILINE).group(1)
condition = condition.removeprefix('${{').removesuffix('}}').strip()

def eligible(build_result, publish_result, is_cancelled, run_proof=True, proof_only=False, publish_enabled=False):
    expression = condition.replace('inputs.run-homebrew-proof', 'run_proof')
    expression = expression.replace('inputs.homebrew-proof-only', 'proof_only')
    expression = expression.replace('inputs.publish-github-release', 'publish_enabled')
    expression = expression.replace('needs.release-interface.result', 'build_result')
    expression = expression.replace('needs.publish-github-release.result', 'publish_result')
    expression = expression.replace('cancelled()', 'is_cancelled')
    expression = expression.replace('&&', ' and ').replace('||', ' or ')
    expression = re.sub(r'!(?!=)', 'not ', expression)
    result = eval(expression, {'__builtins__': {}}, locals())
    if not re.search(r'\b(?:always|cancelled|success|failure)\(', condition):
        result = result and build_result == 'success' and publish_result == 'success' and not is_cancelled
    return result

assert eligible('success', 'skipped', False), 'successful build with publication disabled must reach installed proof'
assert eligible('success', 'success', False)
assert not eligible('failure', 'skipped', False)
assert not eligible('skipped', 'skipped', False)
assert not eligible('success', 'failure', False)
assert not eligible('success', 'cancelled', False)
assert not eligible('success', 'skipped', True)
assert not eligible('success', 'skipped', False, False)
assert eligible('skipped', 'skipped', False, proof_only=True)
assert not eligible('skipped', 'skipped', False, proof_only=True, publish_enabled=True)
assert not eligible('success', 'success', False, proof_only=True, publish_enabled=True)
assert not eligible('skipped', 'skipped', False, run_proof=False, proof_only=True)
assert not eligible('skipped', 'skipped', True, proof_only=True)
assert not eligible('failure', 'skipped', False, proof_only=True)

PY

echo 'fleet-host Homebrew mutations rejected before tool invocation'
