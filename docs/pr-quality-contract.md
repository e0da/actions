# PR Quality Contract

The PR quality workflow checks two things on every pull request event.

## PR body

Under `##` headings, the body has non-empty `Outcome`, `Verification`, and
`Risk and rollback` sections, no `PR_BODY_REQUIRED:` placeholder left, and a
title. Comments and code fences do not count as content. Copy
`templates/pull_request_template.md` to start.

## Review evidence

At least one PR review (not dismissed) or inline review comment on the current
head contains `Verdict: Approve`, in any case. The workflow finds it by itself;
the body needs no link. It does not check who wrote it, because agents and
humans post as the same GitHub user.

A new push changes the head, so the review has to be posted again for that head.

## Adoption

Keep the PR-quality caller separate from broad build CI so body and review
edits rerun this contract alone. The caller needs `contents: read` and
`pull-requests: read`. Trigger on `pull_request`, `pull_request_review`, and
optionally `pull_request_review_comment`. The `projection-label` input is
ignored and only accepted so older callers keep working.
