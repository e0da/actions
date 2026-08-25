#!/usr/bin/env bash
set -euo pipefail

if [[ "$(basename "$0")" == "curl" ]]; then
  output_file=""
  write_format=""
  auth_header=""
  user_credential=""
  scope=""
  url=""

  while (($#)); do
    case "$1" in
      -o)
        output_file="$2"
        shift 2
        ;;
      -w)
        write_format="$2"
        shift 2
        ;;
      -H)
        [[ "$2" == Authorization:* ]] && auth_header="$2"
        shift 2
        ;;
      -u|--user)
        user_credential="$2"
        shift 2
        ;;
      --data-urlencode)
        [[ "$2" == scope=* ]] && scope="${2#scope=}"
        shift 2
        ;;
      --max-filesize)
        shift 2
        ;;
      -sS|--get)
        shift
        ;;
      http*)
        url="$1"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  [[ "$write_format" == "%{http_code}" ]] || exit 90
  if [[ "$url" == "https://ghcr.io/token" ]]; then
    [[ "$user_credential" == "fixture-user:fixture-secret" ]] || exit 91
    [[ "$scope" == "repository:e0da/mcog:pull" ]] || exit 92
    printf 'token|basic|%s\n' "$scope" >> "$MOCK_CURL_LOG"
    case "$MOCK_SCENARIO" in
      token_401)
        printf '{}' > "$output_file"
        printf '401'
        ;;
      token_403)
        printf '{}' > "$output_file"
        printf '403'
        ;;
      token_404)
        printf '{}' > "$output_file"
        printf '404'
        ;;
      empty_token)
        printf '{"token":""}' > "$output_file"
        printf '200'
        ;;
      oversized_token)
        {
          printf '{"token":"'
          awk 'BEGIN { for (i = 0; i < 16385; i++) printf "x" }'
          printf '"}'
        } > "$output_file"
        printf '200'
        ;;
      *)
        printf '{"token":"fixture-bearer-secret"}' > "$output_file"
        printf '200'
        ;;
    esac
    exit 0
  fi

  if [[ "$url" == "https://ghcr.io/v2/e0da/mcog/manifests/sha256:"* ]]; then
    [[ "$auth_header" == "Authorization: Bearer fixture-bearer-secret" ]] || exit 93
    printf 'manifest|bearer\n' >> "$MOCK_CURL_LOG"
    case "$MOCK_SCENARIO" in
      manifest_401) printf '401' ;;
      manifest_403) printf '403' ;;
      manifest_404) printf '404' ;;
      *) printf '200' ;;
    esac
    exit 0
  fi

  exit 94
fi

fail() {
  echo "$1" >&2
  exit 1
}

require_literal() {
  local file="$1"
  local literal="$2"

  grep -F -- "$literal" "$file" >/dev/null || fail "$file missing literal: $literal"
}

reject_literal() {
  local file="$1"
  local literal="$2"

  if grep -F -- "$literal" "$file" >/dev/null; then
    fail "$file should not contain literal: $literal"
  fi
}

workflow=".github/workflows/deploy-k3s.yml"
[[ -f "$workflow" ]] || fail "$workflow is required"

require_literal "$workflow" "      GHCR_TOKEN:"
require_literal "$workflow" "          GH_TOKEN: \${{ secrets.GHCR_TOKEN || github.token }}"
require_literal "$workflow" "          GH_USER: \${{ github.actor }}"
reject_literal "$workflow" "Authorization: Basic \${auth_b64}"

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
mkdir "$fixture_dir/bin"
ln -s "$PWD/tests/deploy_k3s_ghcr_auth.sh" "$fixture_dir/bin/curl"

awk '
  /^      - name: GHCR digest existence check \(fail loud\)$/ { in_step = 1; next }
  in_step && /^        run: \|$/ { in_run = 1; next }
  in_run && /^      - name:/ { exit }
  in_run { sub(/^          /, ""); print }
' "$workflow" > "$fixture_dir/digest-check.sh"
[[ -s "$fixture_dir/digest-check.sh" ]] || fail "could not extract GHCR digest check"

digest="sha256:$(printf 'a%.0s' {1..64})"

run_scenario() {
  local scenario="$1"
  local expected_status="$2"
  local expected_message="$3"
  local output
  local status

  : > "$fixture_dir/curl.log"
  set +e
  output="$(
    PATH="$fixture_dir/bin:$PATH" \
      IMAGE="ghcr.io/e0da/mcog@${digest}" \
      GH_USER="fixture-user" \
      GH_TOKEN="fixture-secret" \
      MOCK_CURL_LOG="$fixture_dir/curl.log" \
      MOCK_SCENARIO="$scenario" \
      bash "$fixture_dir/digest-check.sh" 2>&1
  )"
  status=$?
  set -e

  [[ "$status" == "$expected_status" ]] || fail "$scenario returned $status, expected $expected_status: $output"
  [[ "$output" == *"$expected_message"* ]] || fail "$scenario missing expected message: $output"
  [[ "$output" != *"fixture-secret"* ]] || fail "$scenario exposed the supplied GH token"
  [[ "$output" != *"fixture-bearer-secret"* ]] || fail "$scenario exposed the registry bearer token"
}

run_scenario success 0 "GHCR digest present"
grep -Fx 'token|basic|repository:e0da/mcog:pull' "$fixture_dir/curl.log" >/dev/null || fail "token request did not use repository pull scope"
grep -Fx 'manifest|bearer' "$fixture_dir/curl.log" >/dev/null || fail "manifest request did not use bearer auth"

run_scenario manifest_401 1 "GHCR digest check could not authenticate (HTTP 401)"
run_scenario manifest_403 1 "GHCR digest check could not authenticate (HTTP 403)"
run_scenario manifest_404 1 "image digest not found in GHCR (HTTP 404)"
run_scenario token_401 1 "GHCR token request could not authenticate (HTTP 401)"
run_scenario token_403 1 "GHCR token request could not authenticate (HTTP 403)"
run_scenario token_404 1 "GHCR token endpoint not found (HTTP 404)"
run_scenario empty_token 1 "GHCR token endpoint returned an invalid bearer token"
run_scenario oversized_token 1 "GHCR token endpoint returned an invalid bearer token"

echo "deploy-k3s GHCR bearer auth contract ok"
