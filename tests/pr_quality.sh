#!/bin/sh
set -eu

workflow=.github/workflows/pr-quality.yml
self_workflow=.github/workflows/pr-quality-self.yml
contract_doc=docs/pr-quality-contract.md
readme=README.md

for file in "$workflow" "$self_workflow" "$contract_doc" "$readme"; do
  [ -f "$file" ] || {
    echo "missing PR quality contract file: $file" >&2
    exit 1
  }
done

# shellcheck disable=SC2016
for literal in \
  '    types: [opened, edited, reopened, synchronize, ready_for_review]' \
  '    types: [submitted, edited, dismissed]' \
  '      - name: Enforce PR quality contract' \
  '          [ "$review_commit" = "$live_head" ] || fail "native review commit does not match live PR head"' \
  '            APPROVED|COMMENTED)' \
  '            fail "native review state $review_state is not acceptable"' \
  '          [ -n "$review_text" ] || fail "native review body must contain substantive visible text"' \
  '              fail "a current-head review state is CHANGES_REQUESTED"'
do
  grep -F "$literal" "$workflow" "$self_workflow" >/dev/null || {
    echo "PR quality contract is missing: $literal" >&2
    exit 1
  }
done

for forbidden in \
  E0DA_ADVERSARIAL_REVIEW_RECEIPT_V1 \
  adversarial-review-receipt \
  pr_metadata_digest \
  evidence_digest \
  rubric_digest \
  scripts/pr-quality-review \
  assurance
do
  if rg -F "$forbidden" "$workflow" "$self_workflow" "$contract_doc" "$readme"; then
    echo "PR quality contract still contains retired review bookkeeping: $forbidden" >&2
    exit 1
  fi
done

grep -F 'After repairing a failed prerequisite, classify the newly triggered gate run; an earlier failure is not the current result.' "$contract_doc" >/dev/null || {
  echo "PR quality contract must require a fresh gate result after prerequisite repair" >&2
  exit 1
}

echo "PR quality contract fixtures ok"
