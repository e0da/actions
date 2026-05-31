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

require_literal ".github/workflows/release-rust.yml" "      cargo-package:"
require_literal ".github/workflows/release-rust.yml" "      - name: Install rustup when missing"
require_literal ".github/workflows/release-rust.yml" "pkgid=\"\$(cargo pkgid -p \"\$CARGO_PACKAGE\")\""
require_literal ".github/workflows/release-rust.yml" "cargo build --release --locked --target \${{ matrix.target }} \"\$@\""
reject_literal ".github/workflows/release-rust.yml" "python3 - <<'PY'"
reject_literal ".github/workflows/release-rust.yml" "tomllib"

echo "rust workflows arc readiness ok"
