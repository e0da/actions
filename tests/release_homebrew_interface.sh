#!/bin/sh
set -eu

fail() {
  echo "$1" >&2
  exit 1
}

require_literal() {
  file="$1"
  literal="$2"

  grep -F -- "$literal" "$file" >/dev/null || fail "$file missing literal: $literal"
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

for release_document in \
  docs/release/README.md \
  docs/release/contract.md \
  docs/release/semver-rollups.md \
  docs/release/release-body.md \
  docs/release/evidence.md \
  docs/release/codenames.md \
  docs/release/container-tags.md; do
  [ -f "$release_document" ] || fail "$release_document is required"
done
require_literal "docs/release/README.md" "Canonical release-management contract"
require_literal "docs/release/contract.md" "Actions does not choose a release version"
require_literal "docs/release/semver-rollups.md" "chosen at release cut"
require_literal "docs/release/semver-rollups.md" "git describe --tags --dirty --always"
require_literal "docs/release/semver-rollups.md" "qualitative assessment"
require_literal "docs/release/semver-rollups.md" "does not reopen version selection"
require_literal "docs/release/container-tags.md" "tag@sha256:digest"
require_literal "docs/release/container-tags.md" "Git release tags are immutable"

require_literal "$workflow" "name: Release Homebrew Interface"
require_literal "$workflow" "  workflow_call:"
require_literal "$workflow" "      release-interface:"
require_literal "$workflow" "      build-output-dir:"
require_literal "$workflow" "      built-binary-name:"
require_literal "$workflow" "      artifact-name:"
require_literal "$workflow" "      deterministic-archive:"
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
require_literal "$workflow" "      release-repo:"
require_literal "$workflow" "      release-tag-prefix:"
require_literal "$workflow" "      release-notes-start-tag:"
require_literal "$workflow" "      release-access-scope:"
require_literal "$workflow" "      homebrew-formula-path:"
require_literal "$workflow" "      RELEASE_REPO_TOKEN:"
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
require_literal "$workflow" "DETERMINISTIC_ARCHIVE: \${{ inputs.deterministic-archive }}"
require_literal "$workflow" "# deterministic-archive-script:start"
require_literal "$workflow" "# deterministic-archive-script:end"
require_literal "$workflow" "release-archive-metadata.json"
require_literal "$workflow" "shasum -a 256 \"\$archive\" > \"\$archive.sha256\""
require_literal "$workflow" "if: inputs.publish-github-release && github.ref_type != 'tag'"
require_literal "$workflow" "if: inputs.publish-github-release && github.ref_type == 'tag'"
require_literal "$workflow" "contents: read"
require_literal "$workflow" "contents: write"
require_literal "$workflow" "if: inputs.release-repo != '' && inputs.release-repo != github.repository"
require_literal "$workflow" "RELEASE_REPO_TOKEN secret is required when release-repo differs from the calling repo."
require_literal "$workflow" "GH_TOKEN: \${{ (inputs.release-repo != '' && inputs.release-repo != github.repository) && secrets.RELEASE_REPO_TOKEN || github.token }}"
require_literal "$workflow" "GH_REPO: \${{ inputs.release-repo != '' && inputs.release-repo || github.repository }}"
require_literal "$workflow" "Generate source release notes"
require_literal "$workflow" "repos/\$GITHUB_REPOSITORY/releases/generate-notes"
require_literal "$workflow" "RELEASE_NOTES_START_TAG"
require_literal "$workflow" "derived SemVer release-notes baseline is absent"
require_literal "$workflow" "Upload composed release notes"
require_literal "$workflow" "release-notes.md"
require_literal "$workflow" "--notes-file release-notes.md"
require_literal "$workflow" "Access scope: \$RELEASE_ACCESS_SCOPE"
require_literal "$workflow" "gh release create \"\$DESTINATION_TAG\""
require_literal "$workflow" "gh release download \"\$DESTINATION_TAG\""
require_literal "$workflow" "gh release upload \"\$DESTINATION_TAG\" \"\$asset\""
require_literal "$workflow" "cmp -s \"\$asset\" \"\$existing_release_dir/\$asset\""
require_literal "$workflow" "release asset differs from the existing immutable asset"

if grep -F -- '--clobber' "$workflow" >/dev/null; then
  fail "existing release assets must never be overwritten"
fi
require_literal "$workflow" "body=\$(gh release view \"\$DESTINATION_TAG\" --json body -q .body)"
require_literal "$workflow" "published release notes do not name the source repo/commit"
require_literal "$workflow" "if: inputs.homebrew-formula-path != ''"
require_literal "$workflow" "FORMULA_PATH: \${{ inputs.homebrew-formula-path }}"
require_literal "$workflow" "not found in \$GH_REPO — author it once by hand first"
require_literal "$workflow" "sed -E \"s#^(  url \\\").*(\\\")\\\$#\\\\1\${url}\\\\2#\""
require_literal "$workflow" "sed -E \"s#^(  version \\\").*(\\\")\\\$#\\\\1\${version}\\\\2#\""
require_literal "$workflow" "sed -E \"s#^(  sha256 \\\").*(\\\")\\\$#\\\\1\${sha256}\\\\2#\""
require_literal "$workflow" "gh api -X PUT \"repos/\$GH_REPO/contents/\$FORMULA_PATH\""
require_literal "$workflow" "jq -r '.sha'"
require_literal "$workflow" "jq -r '.content'"
require_literal "$workflow" "grep -qF \"  url \\\"\${url}\\\"\""
require_literal "$workflow" "grep -qF \"  version \\\"\${version}\\\"\""
require_literal "$workflow" "grep -qF \"  sha256 \\\"\${sha256}\\\"\""
require_literal "$workflow" "url line not updated in \$FORMULA_PATH"
require_literal "$workflow" "version line not updated in \$FORMULA_PATH"
require_literal "$workflow" "sha256 line not updated in \$FORMULA_PATH"
require_literal "$workflow" "needs: [release-interface, publish-github-release]"
require_literal "$workflow" "if: inputs.run-homebrew-proof && (needs.publish-github-release.result == 'success' || needs.publish-github-release.result == 'skipped')"
require_literal "$workflow" "CALLER_HOMEBREW_GITHUB_API_TOKEN:"
require_literal "$workflow" "HOMEBREW_GITHUB_API_TOKEN secret is required for e0da/internal Homebrew proof."
require_literal "$workflow" "HOMEBREW_GITHUB_API_TOKEN: \${{ inputs.homebrew-tap == 'e0da/internal' && secrets.HOMEBREW_GITHUB_API_TOKEN || '' }}"
require_literal "$workflow" "GIT_CONFIG_COUNT: \${{ inputs.homebrew-tap == 'e0da/internal' && '1' || '0' }}"
require_literal "$workflow" "GIT_CONFIG_KEY_0: \${{ inputs.homebrew-tap == 'e0da/internal' && format('url.https://x-access-token:{0}@github.com/.insteadOf', secrets.HOMEBREW_GITHUB_API_TOKEN) || '' }}"
require_literal "$workflow" "GIT_CONFIG_VALUE_0: \${{ inputs.homebrew-tap == 'e0da/internal' && 'https://github.com/' || '' }}"
require_literal "$workflow" "brew tap \"\$HOMEBREW_TAP\""
require_literal "$workflow" "brew fetch --force \"\$HOMEBREW_TAP/\$HOMEBREW_FORMULA\""
require_literal "$workflow" "brew install \"\$HOMEBREW_TAP/\$HOMEBREW_FORMULA\""
require_literal "$workflow" "brew uninstall --force \"\$HOMEBREW_TAP/\$HOMEBREW_FORMULA\""
require_literal "$workflow" "brew test \"\$HOMEBREW_TAP/\$HOMEBREW_FORMULA\""

reject_literal "$workflow" "shell: bash"
reject_literal "$workflow" "ruby "
reject_literal "$workflow" "git config --global"

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/home" "$fixture_dir/bin"
cat > "$fixture_dir/home/.gitconfig" <<'EOF'
[user]
	name = Existing Runner User
[safe]
	directory = /unrelated/repository
EOF
cp "$fixture_dir/home/.gitconfig" "$fixture_dir/gitconfig.before"

cat > "$fixture_dir/bin/brew" <<'EOF'
#!/bin/sh
set -eu

case "$MOCK_AUTH_MODE" in
  private)
    [ "$HOMEBREW_GITHUB_API_TOKEN" = "fixture-token" ] || exit 80
    [ "${GIT_CONFIG_COUNT:-}" = "1" ] || exit 81
    [ "${GIT_CONFIG_VALUE_0:-}" = "https://github.com/" ] || exit 82
    [ "$(git config --get user.name)" = "Existing Runner User" ] || exit 83
    [ "$(git config --get "$GIT_CONFIG_KEY_0")" = "https://github.com/" ] || exit 84
    ;;
  public)
    [ -z "${HOMEBREW_GITHUB_API_TOKEN:-}" ] || exit 85
    [ "${GIT_CONFIG_COUNT:-}" = "0" ] || exit 86
    [ -z "${GIT_CONFIG_KEY_0:-}" ] || exit 87
    [ -z "${GIT_CONFIG_VALUE_0:-}" ] || exit 89
    ;;
  *) exit 88 ;;
esac
exit "${MOCK_BREW_EXIT:-0}"
EOF
chmod +x "$fixture_dir/bin/brew"

run_private_brew() {
  mock_exit="$1"
  HOME="$fixture_dir/home" \
    PATH="$fixture_dir/bin:$PATH" \
    MOCK_BREW_EXIT="$mock_exit" \
    MOCK_AUTH_MODE=private \
    HOMEBREW_GITHUB_API_TOKEN=fixture-token \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0="url.https://x-access-token:fixture-token@github.com/.insteadOf" \
    GIT_CONFIG_VALUE_0="https://github.com/" \
    brew tap e0da/internal
}

run_public_brew() {
  HOME="$fixture_dir/home" \
    PATH="$fixture_dir/bin:$PATH" \
    MOCK_AUTH_MODE=public \
    HOMEBREW_GITHUB_API_TOKEN='' \
    GIT_CONFIG_COUNT=0 \
    GIT_CONFIG_KEY_0='' \
    GIT_CONFIG_VALUE_0='' \
    brew tap e0da/beta
}

run_public_brew || fail "public Homebrew command should run without injected credentials"
run_private_brew 0 || fail "process-scoped Git auth should reach a successful private Homebrew command"
cmp -s "$fixture_dir/gitconfig.before" "$fixture_dir/home/.gitconfig" ||
  fail "successful Homebrew command changed preexisting global Git config"

failure_exit=0
run_private_brew 23 || failure_exit=$?
[ "$failure_exit" -eq 23 ] || fail "fixture Homebrew failure should propagate unchanged"
cmp -s "$fixture_dir/gitconfig.before" "$fixture_dir/home/.gitconfig" ||
  fail "failed Homebrew command changed preexisting global Git config"

echo "release homebrew interface workflow ok"
