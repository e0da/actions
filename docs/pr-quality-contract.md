# PR Quality Contract

**Linear:** E0D-1669

The PR quality workflow verifies that a pull request has complete delivery
metadata and a substantive native GitHub review for its current head. On
success it projects the configured `approved[pr-reviewer]` label. The label is
only a readable projection; it does not authorize a merge.

## PR body

The PR body must contain `<!-- e0da-pr-body:v1 -->` and non-empty `Outcome`,
`Verification`, `Risk and rollback`, `Linear`, and `Adversarial review`
sections. The review section contains one native review link for the same PR.

## Review

The linked native review must be `APPROVED` or `COMMENTED`, point at the current
head, and contain substantive visible text. A normal technical review records
its verdict, technical findings, and verification. The workflow rejects a
current-head `CHANGES_REQUESTED` state and rechecks live review state before and
after projecting its label.

After repairing a failed prerequisite, classify the newly triggered gate run; an earlier failure is not the current result.

## Adoption

Keep the PR-quality caller separate from broad build CI so PR-body and review
edits rerun this contract without rerunning unrelated checks. The caller needs
`contents: read`, `issues: write`, and `pull-requests: write` permissions.
