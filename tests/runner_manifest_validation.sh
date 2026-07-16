#!/bin/sh
set -eu

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT INT TERM

validate_runner_manifest() {
  [ -n "$RUNNER_MANIFEST" ] || return 0

  if ! command -v jq >/dev/null 2>&1; then
    echo "::error::runner-manifest was provided, but jq was not found."
    return 1
  fi

  schema="$(printf '%s' "$RUNNER_MANIFEST" | jq -r '.schema_version // ""')"
  if [ "$schema" != "puck-linux-runner-image-contract.v1" ]; then
    echo "::error::runner-manifest schema_version must be puck-linux-runner-image-contract.v1, got '${schema:-<missing>}'."
    return 1
  fi

  repo="${REPOSITORY#*/}"
  runner_entry="$(printf '%s' "$RUNNER_MANIFEST" | jq -c --arg repo "$repo" '.runners[]? | select(.runner_identity.repo == $repo)' | sed -n '1p')"
  if [ -z "$runner_entry" ]; then
    echo "::error::runner-manifest missing runners[].runner_identity.repo entry for '${repo}'."
    return 1
  fi

  manifest_profile="$(printf '%s' "$runner_entry" | jq -r '.runner_identity.runner_profile // ""')"
  if [ -n "$RUNNER_PROFILE" ] && [ "$manifest_profile" != "$RUNNER_PROFILE" ]; then
    echo "::error::runner-manifest runner_identity.runner_profile expected '${RUNNER_PROFILE}', got '${manifest_profile:-<missing>}'."
    return 1
  fi

  manifest_os="$(printf '%s' "$runner_entry" | jq -r '.intended_contract_state.runner_os // ""')"
  if [ -n "$manifest_os" ] && [ "$manifest_os" != "$OBSERVED_RUNNER_OS" ]; then
    echo "::error::runner-manifest intended_contract_state.runner_os expected '${OBSERVED_RUNNER_OS}', got '${manifest_os}'."
    return 1
  fi

  manifest_arch="$(printf '%s' "$runner_entry" | jq -r '.intended_contract_state.runner_arch // ""')"
  if [ -n "$manifest_arch" ] && [ "$manifest_arch" != "$OBSERVED_RUNNER_ARCH" ]; then
    echo "::error::runner-manifest intended_contract_state.runner_arch expected '${OBSERVED_RUNNER_ARCH}', got '${manifest_arch}'."
    return 1
  fi

  if [ "$manifest_profile" = "puck-linux-arm64" ]; then
    runner_local_bin_path="$(printf '%s' "$runner_entry" | jq -r '.path_policy.runner_local_bin.path // ""')"
    if [ "$runner_local_bin_path" != "/runner/.local/bin" ]; then
      echo "::error::runner-manifest path_policy.runner_local_bin.path expected '/runner/.local/bin', got '${runner_local_bin_path:-<missing>}'."
      return 1
    fi

    runner_local_bin_state="$(printf '%s' "$runner_entry" | jq -r '.path_policy.runner_local_bin.state // ""')"
    if [ "$runner_local_bin_state" != "directory" ]; then
      echo "::error::runner-manifest path_policy.runner_local_bin.state expected 'directory', got '${runner_local_bin_state:-<missing>}'."
      return 1
    fi

    if ! printf '%s' "$runner_entry" | jq -e '.path_policy.runner_local_bin.in_path == true' >/dev/null; then
      runner_local_bin_in_path="$(printf '%s' "$runner_entry" | jq -r '.path_policy.runner_local_bin.in_path // false')"
      echo "::error::runner-manifest path_policy.runner_local_bin.in_path expected boolean true, got '${runner_local_bin_in_path}'."
      return 1
    fi
  fi

  manifest_capabilities="$RUNNER_CAPABILITIES"
  if [ "${TOOL_MODE:-}" = runner-preinstalled ]; then
    manifest_capabilities="${manifest_capabilities}${manifest_capabilities:+ }lychee"
  fi

  for capability in $manifest_capabilities; do
    tool_status="$(printf '%s' "$runner_entry" | jq -r --arg name "$capability" '([.tools[]? | select(.name == $name)] | first | .observed.status) // "missing-tool-entry"')"
    if [ "$tool_status" != "present" ]; then
      echo "::error::runner-manifest tools.${capability}.observed.status expected 'present', got '${tool_status}'."
      return 1
    fi

    tool_version="$(printf '%s' "$runner_entry" | jq -r --arg name "$capability" '([.tools[]? | select(.name == $name)] | first | .observed.version) // ""')"
    if [ -z "$tool_version" ]; then
      echo "::error::runner-manifest tools.${capability}.observed.version expected a non-empty version."
      return 1
    fi
  done
}

manifest_path="$tmpdir/manifest.json"
cat > "$manifest_path" <<'JSON'
{
  "schema_version": "puck-linux-runner-image-contract.v1",
  "runners": [
    {
      "runner_identity": {
        "repo": "stack",
        "runner_profile": "puck-linux-arm64"
      },
      "intended_contract_state": {
        "runner_os": "Linux",
        "runner_arch": "ARM64"
      },
      "path_policy": {
        "runner_local_bin": {
          "path": "/runner/.local/bin",
          "state": "directory",
          "in_path": true
        }
      },
      "tools": [
        {
          "name": "lychee",
          "observed": {
            "status": "present",
            "path": "/runner/.local/bin/lychee",
            "version": "lychee 0.23.0"
          }
        },
        {
          "name": "gh",
          "observed": {
            "status": "missing",
            "path": null,
            "version": null
          }
        },
        {
          "name": "bun",
          "observed": {
            "status": "present",
            "path": "/runner/.local/bin/bun",
            "version": "1.2.18"
          }
        },
        {
          "name": "jq",
          "observed": {
            "status": "present",
            "path": "/usr/bin/jq",
            "version": "jq-1.7.1"
          }
        }
      ]
    }
  ]
}
JSON

RUNNER_MANIFEST="$(cat "$manifest_path")"
RUNNER_PROFILE=puck-linux-arm64
RUNNER_CAPABILITIES=lychee
TOOL_MODE=workflow-install
OBSERVED_RUNNER_OS=Linux
OBSERVED_RUNNER_ARCH=ARM64
REPOSITORY=e0da/stack
validate_runner_manifest

RUNNER_CAPABILITIES="bun jq"
validate_runner_manifest

expect_failure() {
  name=$1
  expected=$2
  shift 2
  if "$@" > "$tmpdir/${name}.out" 2>&1; then
    echo "expected failure: $name" >&2
    exit 1
  fi
  grep -F "$expected" "$tmpdir/${name}.out" >/dev/null
}

RUNNER_CAPABILITIES=bun
RUNNER_MANIFEST="$(jq '(.runners[0].tools[] | select(.name == "bun") | .observed.status) = "missing"' "$manifest_path")"
expect_failure bun_missing "tools.bun.observed.status expected 'present', got 'missing'" validate_runner_manifest

RUNNER_CAPABILITIES=jq
RUNNER_MANIFEST="$(jq '(.runners[0].tools[] | select(.name == "jq") | .observed.version) = ""' "$manifest_path")"
expect_failure jq_missing_version "tools.jq.observed.version expected a non-empty version" validate_runner_manifest

RUNNER_MANIFEST="$(cat "$manifest_path")"
RUNNER_CAPABILITIES=lychee
RUNNER_PROFILE=hosted-linux
expect_failure wrong_profile "runner_identity.runner_profile expected 'hosted-linux'" validate_runner_manifest

RUNNER_PROFILE=puck-linux-arm64
OBSERVED_RUNNER_ARCH=X64
expect_failure wrong_arch "intended_contract_state.runner_arch expected 'X64'" validate_runner_manifest

OBSERVED_RUNNER_ARCH=ARM64
RUNNER_CAPABILITIES=gh
expect_failure missing_tool "tools.gh.observed.status expected 'present', got 'missing'" validate_runner_manifest

RUNNER_CAPABILITIES=lychee
RUNNER_MANIFEST="$(jq '(.runners[0].tools[] | select(.name == "lychee") | .observed.version) = ""' "$manifest_path")"
expect_failure missing_version "tools.lychee.observed.version expected a non-empty version" validate_runner_manifest

RUNNER_MANIFEST="$(cat "$manifest_path")"
REPOSITORY=e0da/ops
expect_failure missing_repo "missing runners[].runner_identity.repo entry for 'ops'" validate_runner_manifest

RUNNER_MANIFEST="$(cat "$manifest_path")"
REPOSITORY=e0da/stack
RUNNER_CAPABILITIES=
TOOL_MODE=runner-preinstalled
validate_runner_manifest

RUNNER_MANIFEST="$(jq '(.runners[0].tools[] | select(.name == "lychee") | .observed.status) = "missing"' "$manifest_path")"
expect_failure implied_lychee_missing "tools.lychee.observed.status expected 'present', got 'missing'" validate_runner_manifest

RUNNER_MANIFEST="$(jq '.runners[0].path_policy.runner_local_bin.path = "/tmp/bin"' "$manifest_path")"
expect_failure runner_local_bin_wrong_path "path_policy.runner_local_bin.path expected '/runner/.local/bin', got '/tmp/bin'" validate_runner_manifest

RUNNER_MANIFEST="$(jq '.runners[0].path_policy.runner_local_bin.state = "missing"' "$manifest_path")"
expect_failure runner_local_bin_missing "path_policy.runner_local_bin.state expected 'directory', got 'missing'" validate_runner_manifest

RUNNER_MANIFEST="$(jq '.runners[0].path_policy.runner_local_bin.in_path = false' "$manifest_path")"
expect_failure runner_local_bin_not_in_path "path_policy.runner_local_bin.in_path expected boolean true, got 'false'" validate_runner_manifest

RUNNER_MANIFEST="$(jq '.runners[0].path_policy.runner_local_bin.in_path = "true"' "$manifest_path")"
expect_failure runner_local_bin_in_path_wrong_type "path_policy.runner_local_bin.in_path expected boolean true, got 'true'" validate_runner_manifest

echo "runner manifest validation ok"
