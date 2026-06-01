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

require_literal ".github/workflows/ci-rust.yml" "      - name: Install rustup when missing"
require_literal ".github/workflows/ci-rust.yml" "https://sh.rustup.rs"
require_literal ".github/workflows/ci-rust.yml" "RUST_TOOLCHAIN: \${{ inputs.toolchain }}"
require_literal ".github/workflows/ci-rust.yml" "rust_toolchain_ready()"
require_literal ".github/workflows/ci-rust.yml" "rustup run \"\$RUST_TOOLCHAIN\" cargo clippy --version"
require_literal ".github/workflows/ci-rust.yml" "rustup run \"\$RUST_TOOLCHAIN\" rustfmt --version"
require_literal ".github/workflows/ci-rust.yml" "Using preinstalled Rust toolchain: \$RUST_TOOLCHAIN"
require_literal ".github/workflows/ci-rust.yml" "while [ \"\$attempt\" -le 3 ]; do"
require_literal ".github/workflows/ci-rust.yml" "rustup install attempt \${attempt} failed; retrying in \${sleep_seconds}s"

require_literal ".github/workflows/release-rust.yml" "      cargo-package:"
require_literal ".github/workflows/release-rust.yml" "      - name: Install rustup when missing"
require_literal ".github/workflows/release-rust.yml" "pkgid=\"\$(cargo pkgid -p \"\$CARGO_PACKAGE\")\""
require_literal ".github/workflows/release-rust.yml" "build-matrix: \${{ steps.meta.outputs.build-matrix }}"
require_literal ".github/workflows/release-rust.yml" "matrix: \${{ fromJSON(needs.validate.outputs.build-matrix) }}"
require_literal ".github/workflows/release-rust.yml" "unsupported release target:"
require_literal ".github/workflows/release-rust.yml" "cargo build --release --locked --target \${{ matrix.target }} \"\$@\""
require_literal ".github/workflows/release-rust.yml" "RUST_TARGET: \${{ matrix.target }}"
require_literal ".github/workflows/release-rust.yml" "rust_metadata_toolchain_ready()"
require_literal ".github/workflows/release-rust.yml" "rust_target_toolchain_ready()"
require_literal ".github/workflows/release-rust.yml" "rustup target list --toolchain \"\$RUST_TOOLCHAIN\" --installed"
require_literal ".github/workflows/release-rust.yml" "Using preinstalled Rust target toolchain: \$RUST_TOOLCHAIN / \$RUST_TARGET"
require_literal ".github/workflows/release-rust.yml" "rustup install attempt \${attempt} failed; retrying in \${sleep_seconds}s"
reject_literal ".github/workflows/release-rust.yml" "      - name: Check if target is requested"
reject_literal ".github/workflows/release-rust.yml" "python3 - <<'PY'"
reject_literal ".github/workflows/release-rust.yml" "tomllib"

echo "rust workflows arc readiness ok"
