# PR Quality Contract

The workflow checks the PR description. Under `##` headings, the body has non-empty `Outcome`, `Verification`, and `Risk and rollback` sections, no `PR_BODY_REQUIRED:` placeholder, and a title. Comments and code fences do not count as content. Copy `templates/pull_request_template.md` to start.

It does not look up reviews or require a `Verdict: Approve` comment. Repository branch protection owns any independent-approval requirement. A self-authored verdict is not independent review.

Keep the caller separate from build CI so description edits rerun only this check. The caller needs `contents: read` and `pull-requests: read`; trigger it on `pull_request` metadata changes. Existing review-event callers remain compatible but are unnecessary. The ignored `projection-label` input remains accepted for existing callers.
