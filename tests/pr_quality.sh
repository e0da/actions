#!/bin/sh
set -eu

workflow=.github/workflows/pr-quality.yml
ruby tests/pr_quality_concurrency.rb
template=templates/pull_request_template.md
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

awk '/^        run: \|$/ { on=1; next } on { sub(/^          /, ""); print }' "$workflow" > "$tmp/gate.sh"
[ -s "$tmp/gate.sh" ] || { echo "could not extract gate script" >&2; exit 1; }

for banned in projection PROJECTION_LABEL Adversarial pullrequestreview issues:; do
  if grep -F "$banned" "$tmp/gate.sh" >/dev/null; then
    echo "gate still contains retired ceremony: $banned" >&2
    exit 1
  fi
done

mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/bin/sh
file="$FIX/pr.json"
case "$2" in
  */reviews) file="$FIX/reviews" ;;
  */comments) file="$FIX/comments" ;;
esac
filter=""
while [ $# -gt 0 ]; do
  [ "$1" = "--jq" ] && filter="$2"
  shift
done
if [ -n "$filter" ]; then jq -c "$filter" "$file"; else cat "$file"; fi
STUB
chmod +x "$tmp/bin/gh"

HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
OLD=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
GOOD_BODY='## Outcome\n\nDone.\n\n## Verification\n\nRan it.\n\n## Risk and rollback\n\nRevert.\n'

# run_case NAME EXPECT BODY REVIEWS COMMENTS
run_case() {
  name="$1" expect="$2" body="$3" reviews="$4" comments="$5"
  FIX="$tmp/$name"
  mkdir "$FIX"
  printf '{"title":"t","head":{"sha":"%s"},"body":"%s"}' "$HEAD" "$body" > "$FIX/pr.json"
  printf '[%s]\n' "$reviews" > "$FIX/reviews"
  printf '[%s]\n' "$comments" > "$FIX/comments"
  if FIX="$FIX" PATH="$tmp/bin:$PATH" REPOSITORY=o/r PULL_REQUEST_NUMBER=1 RUNNER_TEMP="$tmp" \
    sh "$tmp/gate.sh" >/dev/null 2>"$tmp/err"; then
    result=pass
  else
    result=fail
  fi
  [ "$result" = "$expect" ] || { echo "case $name: expected $expect, got $result" >&2; cat "$tmp/err" >&2; exit 1; }
}

review() { printf '{"commit_id":"%s","state":"%s","body":"%s"}' "$1" "$2" "$3"; }
comment() { printf '{"commit_id":"%s","body":"%s"}' "$1" "$2"; }

run_case approve_review pass "$GOOD_BODY" "$(review $HEAD COMMENTED 'Verdict: Approve')" ''
run_case approve_lowercase_inline pass "$GOOD_BODY" '' "$(comment $HEAD 'ok. verdict: approve')"
run_case stale_head fail "$GOOD_BODY" "$(review $OLD APPROVED 'Verdict: Approve')" ''
run_case dismissed fail "$GOOD_BODY" "$(review $HEAD DISMISSED 'Verdict: Approve')" ''
run_case no_verdict fail "$GOOD_BODY" "$(review $HEAD APPROVED 'looks fine')" ''
run_case missing_section fail '## Outcome\n\nDone.\n\n## Verification\n\nRan it.\n' "$(review $HEAD COMMENTED 'Verdict: Approve')" ''
run_case empty_section fail '## Outcome\n\n<!-- hi -->\n\n## Verification\n\nx\n\n## Risk and rollback\n\ny\n' "$(review $HEAD COMMENTED 'Verdict: Approve')" ''
run_case placeholder fail '## Outcome\n\nPR_BODY_REQUIRED:OUTCOME\n\n## Verification\n\nx\n\n## Risk and rollback\n\ny\n' "$(review $HEAD COMMENTED 'Verdict: Approve')" ''

for heading in Outcome Verification 'Risk and rollback'; do
  grep -Fx "## $heading" "$template" >/dev/null || { echo "template missing: $heading" >&2; exit 1; }
done

echo "PR quality contract fixtures ok"
