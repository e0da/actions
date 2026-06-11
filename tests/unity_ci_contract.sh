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

workflow=".github/workflows/ci-unity.yml"
[ -f "$workflow" ] || fail "$workflow is required"

require_literal "$workflow" "name: CI Unity"
require_literal "$workflow" "  workflow_call:"
require_literal "$workflow" "      runner:"
require_literal "$workflow" "        default: puck-macos-arm64"
require_literal "$workflow" "      runner-profile:"
require_literal "$workflow" "        default: puck-macos-arm64"
require_literal "$workflow" "      unity-version:"
require_literal "$workflow" "        default: 6000.3.2f1"
require_literal "$workflow" "      project-path:"
require_literal "$workflow" "        required: true"
require_literal "$workflow" "      check-command:"
require_literal "$workflow" "      run-tests:"
require_literal "$workflow" "      test-platform:"
require_literal "$workflow" "      build-target:"
require_literal "$workflow" "        default: Android"
require_literal "$workflow" "      build-method:"
require_literal "$workflow" "        required: true"
require_literal "$workflow" "      build-output-dir:"
require_literal "$workflow" "      artifact-name:"
require_literal "$workflow" "    runs-on: \${{ inputs.runner }}"
require_literal "$workflow" "      - name: Validate runner contract"
require_literal "$workflow" "puck-macos-arm64) require_runner macOS ARM64 ;;"
require_literal "$workflow" "      - name: Check out repository"
require_literal "$workflow" "          lfs: true"
require_literal "$workflow" "      - name: Validate Unity inputs"
require_literal "$workflow" "Unity project does not declare m_EditorVersion: \$UNITY_VERSION"
require_literal "$workflow" "      - name: Validate Unity editor and Android module"
require_literal "$workflow" "Unity Android Build Support not found"
require_literal "$workflow" "\"\$android_player/SDK\" \"\$android_player/NDK\" \"\$android_player/OpenJDK\""
require_literal "$workflow" "      - name: Run repository checks"
require_literal "$workflow" "run: sh -c \"\$CHECK_COMMAND\""
require_literal "$workflow" "      - name: Open Unity project"
require_literal "$workflow" "-projectPath \"\$PROJECT_PATH\""
require_literal "$workflow" "      - name: Run Unity tests"
require_literal "$workflow" "-runTests"
require_literal "$workflow" "-testResults \"\$TEST_RESULTS_DIR/\${TEST_PLATFORM}.xml\""
require_literal "$workflow" "      - name: Build Android player"
require_literal "$workflow" "UNITY_BUILD_OUTPUT_DIR: \${{ inputs['build-output-dir'] }}"
require_literal "$workflow" "-buildTarget \"\$BUILD_TARGET\""
require_literal "$workflow" "-executeMethod \"\$BUILD_METHOD\""
require_literal "$workflow" "      - name: Validate build artifact"
require_literal "$workflow" "      - name: Upload Unity build artifact"
require_literal "$workflow" "uses: actions/upload-artifact@v7"
require_literal "$workflow" "      - name: Upload Unity logs"
require_literal "$workflow" "if: always()"

echo "unity ci workflow contract ok"
