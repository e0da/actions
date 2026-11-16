#!/bin/sh
set -eu

workflow=.github/workflows/ci-wiki-bundled.yml
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

awk '
  $0 == "      - name: Set up Ruby" { in_step=1; next }
  in_step && $0 == "        run: |" { in_run=1; next }
  in_run {
    if ($0 ~ /^          /) { sub(/^          /, ""); print; next }
    if ($0 == "") { print; next }
    exit
  }
' "$workflow" > "$tmpdir/ruby-setup.sh"
[ -s "$tmpdir/ruby-setup.sh" ]
bash -n "$tmpdir/ruby-setup.sh"
mkdir -p "$tmpdir/bin"

cat > "$tmpdir/bin/brew" <<'SH'
#!/bin/sh
set -eu
case "$*" in
  'info ruby@3.2'|'list ruby@3.2') ;;
  '--prefix ruby@3.2') printf '%s\n' "$FIXTURE_ROOT/ruby" ;;
  '--prefix openssl@3')
    [ "${PREFIX_UNAVAILABLE:-0}" = 0 ] || exit 19
    printf '%s\n' '/fixture/OpenSSL 3'
    ;;
  *) echo "unexpected Homebrew call" >&2; exit 1 ;;
esac
SH
cat > "$tmpdir/bin/ruby" <<'SH'
#!/bin/sh
set -eu
case "$1" in
  --version) echo 'fixture Ruby' ;;
  -rbundler)
    if [ "${CONFIGURED_BUILD+x}" = x ]; then printf false; else printf true; fi
    ;;
  *) exit 1 ;;
esac
SH
cat > "$tmpdir/bin/gem" <<'SH'
#!/bin/sh
exit 0
SH
cat > "$tmpdir/bin/bundle" <<'SH'
#!/bin/sh
set -eu
case "$*" in
  'config set --local path '*) ;;
  'install --jobs 4 --retry 3')
    printf '%s' "${BUNDLE_BUILD__OPENSSL-${CONFIGURED_BUILD-<unset>}}" > "$FIXTURE_ROOT/observed"
    ;;
  *) exit 1 ;;
esac
SH
chmod +x "$tmpdir/bin/"*

FIXTURE_ROOT="$tmpdir"
PATH="$tmpdir/bin:$PATH"
RUBY_VERSION=3.2
RUNNER_TEMP="$tmpdir"
GITHUB_PATH="$tmpdir/github-path"
export FIXTURE_ROOT PATH RUBY_VERSION RUNNER_TEMP GITHUB_PATH
unset BUNDLE_BUILD__OPENSSL CONFIGURED_BUILD

bash -e "$tmpdir/ruby-setup.sh"
[ "$(cat "$tmpdir/observed")" = '--with-openssl-dir=/fixture/OpenSSL 3' ] || {
  echo 'native build did not select one OpenSSL 3 prefix' >&2
  exit 1
}

CONFIGURED_BUILD='--with-openssl-dir=/caller/SSL'
BUNDLE_BUILD__OPENSSL="$CONFIGURED_BUILD"
export CONFIGURED_BUILD BUNDLE_BUILD__OPENSSL
bash -e "$tmpdir/ruby-setup.sh"
[ "$(cat "$tmpdir/observed")" = "$CONFIGURED_BUILD" ]

unset BUNDLE_BUILD__OPENSSL
bash -e "$tmpdir/ruby-setup.sh"
[ "$(cat "$tmpdir/observed")" = "$CONFIGURED_BUILD" ]

CONFIGURED_BUILD=''
export CONFIGURED_BUILD
bash -e "$tmpdir/ruby-setup.sh"
[ "$(cat "$tmpdir/observed")" = '' ]

unset CONFIGURED_BUILD
rm "$tmpdir/observed"
if PREFIX_UNAVAILABLE=1 bash -e "$tmpdir/ruby-setup.sh"; then
  echo 'missing OpenSSL prefix unexpectedly accepted' >&2
  exit 1
fi
[ ! -f "$tmpdir/observed" ]
echo 'Wiki Ruby OpenSSL build selection fixture passed'
