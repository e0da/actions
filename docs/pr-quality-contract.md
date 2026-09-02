# PR Quality Contract

**Linear:** E0D-1667

## Purpose

The PR quality workflow makes three delivery facts mechanically visible:

1. the pull request explains its outcome, verification, risk, Linear ownership,
   and adversarial review;
2. a native GitHub review carries a structured receipt for the exact live head
   and reviewed PR metadata;
3. the readable `approved[pr-reviewer]` label reflects the current gate result.

The native review object and its receipt are evidence. The label is only a
projection. It cannot authorize a merge, and the workflow never creates,
removes, or interprets the human-reserved `approved[e0da]` label.

This contract supersedes neither GitHub branch protection nor Agency merge
authority. The existing `approval-gate.yml` workflow remains an advisory
compatibility report.

The May 2026 Puck approval-policy pivot correctly stopped using the old
approval report as a required build-health check. This separately named
contract does not reverse or mutate that historical workflow. It is a narrower
policy gate for complete PR metadata and exact-head adversarial-review proof.
Its expected red state before review means “not review-ready,” not “the build
failed.” Ops rollout may require this new check while preserving the older
decision and compatibility surface.

## PR body contract

Copy [`templates/pull_request_template.md`](../templates/pull_request_template.md)
to `.github/pull_request_template.md` in each adopting repository. The template
contains this version marker:

```text
<!-- e0da-pr-body:v1 -->
```

It also contains section-specific poison values with the stable prefix
`PR_BODY_REQUIRED:`. Every poison value must be replaced. The gate then requires
non-comment content under each exact heading:

- `Outcome`
- `Verification`
- `Risk and rollback`
- `Linear`
- `Adversarial review`

The adversarial-review section must contain exactly one native review link for
the same repository and PR:

```text
https://github.com/OWNER/REPOSITORY/pull/NUMBER#pullrequestreview-ID
```

An issue comment, commit comment, check output, label, or approval-looking text
does not satisfy this reference.

## Native review receipt

The linked native review remains human-first Markdown in the canonical `$rvw`
shape. Its first visible nonblank line must be `Recommendation: Approve`, its
`Blockers:` list must normalize exactly to `- none`, and its `Nits:` list must
contain at least one item. No other visible prose is accepted. Embed exactly
one machine receipt block anywhere in that review:

````markdown
Recommendation: Approve

Blockers:
- none

Nits:
- none

<!-- E0DA_ADVERSARIAL_REVIEW_RECEIPT_V1
{
  "schema": "e0da.adversarial-review-receipt/v1",
  "repository": "OWNER/REPOSITORY",
  "pull_request": 123,
  "head_sha": "LIVE_40_CHARACTER_COMMIT_SHA",
  "pr_metadata_digest": "sha256:DIGEST_OF_REVIEWED_TITLE_AND_BODY",
  "reviewer": {
    "id": "agent:REVIEWER_ID",
    "github_login": "NATIVE_REVIEW_PUBLISHER"
  },
  "session": {
    "id": "HARNESS_SESSION_ID",
    "tool": "codex"
  },
  "rubric": {
    "id": "e0da.adversarial-pr-review",
    "version": "1",
    "digest": "sha256:DIGEST_OF_CANONICAL_RUBRIC_WITHOUT_DIGEST",
    "checks": ["correctness", "verification", "risk", "scope"]
  },
  "verdict": "APPROVE",
  "assurance": "independent",
  "findings": [],
  "evidence": [
    {
      "kind": "command",
      "subject": "sh tests/example.sh",
      "result": "pass"
    }
  ],
  "evidence_digest": "sha256:DIGEST_OF_CANONICAL_EVIDENCE"
}
-->
````

The gate verifies:

- the native review URL resolves to the referenced review object;
- receipt repository and PR number match the live pull request;
- review `commit_id`, receipt `head_sha`, and live PR head are identical;
- reviewed title and required body content match the receipt metadata digest;
- reviewer, session, rubric, verdict, findings, and evidence are structured;
- rubric id/version are canonical and its checks include correctness,
  verification, risk, and scope;
- receipt reviewer login matches the native review publisher;
- the visible review recommendation is approving and its blocker list is
  canonically empty;
- the verdict is `APPROVE`;
- every finding is explicitly `resolved` with a non-empty resolution;
- every evidence item reports `pass`;
- rubric and evidence SHA-256 digests match their canonical JSON;
- no reviewer's latest decisive current-head state is `CHANGES_REQUESTED`;
- post-projection live head, reviewed metadata, linked-review state, and latest
  decisive review states still match.

Canonical JSON is compact JSON with recursively sorted object keys. Neither
serialization includes a trailing newline. The rubric digest covers
`.rubric | del(.digest)`, and the evidence digest covers `.evidence`:

```sh
rubric_material="$(jq -cS '.rubric | del(.digest)' receipt.json)"
printf '%s' "$rubric_material" | shasum -a 256

evidence_material="$(jq -cS '.evidence' receipt.json)"
printf '%s' "$evidence_material" | shasum -a 256
```

On Linux, replace `shasum -a 256` with `sha256sum`.

Evidence entries are observations asserted by the native review publisher. The
gate checks their structure, passing result, and aggregate digest; it does not
re-execute commands or independently authenticate an observation. Reviewers
should use a durable run URL, artifact digest, or timestamped receipt as the
evidence `subject` when one exists, and use the human review to state any
remaining evidence limitation.

The metadata digest covers this canonical object:

```json
{
  "body_version": "e0da-pr-body:v1",
  "title": "THE EXACT PR TITLE",
  "sections": {
    "Outcome": "NORMALIZED SECTION CONTENT",
    "Verification": "NORMALIZED SECTION CONTENT",
    "Risk and rollback": "NORMALIZED SECTION CONTENT",
    "Linear": "NORMALIZED SECTION CONTENT",
    "Adversarial review": "<native-review>"
  }
}
```

Normalization converts CRLF to LF and removes leading and trailing spaces,
tabs, and newlines from each section. Internal Markdown remains exact. HTML
comments and fenced code blocks are removed before headings, human review
controls, and metadata are parsed, so hidden or example-only text cannot
satisfy the contract. The version marker and poison values are checked in the
raw body. The constant adversarial-review value avoids a circular dependency:
publish the review first, then add its native link to the PR body. Editing the
title or any other required section invalidates the receipt without requiring
a new commit.

### Publish with the helper

Agents should not hand-calculate these fields. From an adopting repository,
prepare a human review and evidence array:

```markdown
<!-- review.md -->
Recommendation: Approve

Blockers:
- none

Nits:
- none
```

```json
[
  {
    "kind": "command",
    "subject": "bun run check",
    "result": "pass"
  }
]
```

Then run the Actions-owned helper from the PR branch:

```sh
~/src/actions/scripts/pr-quality-review \
  --reviewer agent:hypatia \
  --session SESSION_ID \
  --review-file review.md \
  --evidence-file evidence.json
```

The helper discovers the current repository and PR, fetches live metadata,
uses the fixed rubric, computes all three digests, publishes the native review,
and replaces the adversarial-review poison value or prior pointer with the
returned native review URL. It reuses an identical exact-head review when one
already exists, then re-reads the PR head, title, and body before patching. If
review publication succeeds but the body update fails, rerunning the command
therefore resumes from the existing review instead of publishing a duplicate.
Pass `--repo OWNER/REPO` and `--pr NUMBER` outside the PR checkout. `--tool`
defaults to `codex`; `--findings-file` accepts a JSON array whose entries are
already resolved. Run `--help` for the complete shape.

The helper reads the authenticated GitHub login. It publishes `APPROVE` with
independent assurance when that login differs from the PR publisher, or
`COMMENT` with reduced assurance when they are the same. It refuses review
Markdown that does not match canonical `$rvw` controls, non-passing evidence,
unresolved findings, ambiguous body headings, and untouched non-review poison
values before publishing.

### Current review state

The gate streams every native review from every paginated page into one local
array, then considers reviews bound to the current head. For each reviewer, it
selects the latest decisive state by submission time and review ID. Decisive states are
`APPROVED`, `CHANGES_REQUESTED`, and `DISMISSED`; a later `COMMENTED` review
does not silently clear requested changes. Any latest `CHANGES_REQUESTED` state
blocks the gate. A later `APPROVED` or `DISMISSED` state supersedes it.

### Assurance modes

An independent GitHub identity publishes an `APPROVED` review and declares
`"assurance": "independent"`.

When the authoring and reviewing agents share the PR publisher's GitHub
identity, GitHub does not allow that identity to approve its own PR. A native
`COMMENTED` review from the PR publisher may therefore declare
`"assurance": "reduced"`. This path remains explicit in the check summary and
does not pretend to be independent approval. A `COMMENTED` review from any
other publisher fails.

`CHANGES_REQUESTED`, reviewer identity mismatch, malformed receipt, stale
head, post-review metadata edits, unresolved findings, failed evidence, or a
digest mismatch fails the gate.

## Projection label

Create the agent-owned label once in each adopting repository:

```sh
gh label create 'approved[pr-reviewer]' \
  --color 1D76DB \
  --description 'Exact-head adversarial PR review receipt is valid'
```

The label name is configurable, but it must match `approved[<agent-id>]` and
cannot be `approved[e0da]`.

On success, the workflow adds its configured label. On failure, it reads live
labels and removes only that exact label when present. It does not suppress API
or permission failures while clearing a stale projection. Per-PR concurrency
lets the active run finish and retains only the newest pending event; GitHub may
replace an older pending event. A new commit, edited PR body, submitted or
edited review, or dismissed review reruns the contract. The gate re-reads PR
metadata and decisive review state after writing the label; later events
recompute the projection again. GitHub does not offer an atomic transaction
across independent API reads and label mutation, so the label remains an
eventually consistent projection rather than authority.

The workflow expects its projection label to exist. This keeps repository label
creation deliberate and makes a misspelled label a visible configuration error.

## Adoption

Keep this gate in its own caller so body and review edits do not rerun broad
build CI:

```yaml
name: PR Quality

on:
  pull_request:
    types: [opened, edited, reopened, synchronize, ready_for_review]
  pull_request_review:
    types: [submitted, edited, dismissed]

permissions:
  contents: read
  issues: write
  pull-requests: write

jobs:
  pr-quality:
    name: PR Quality
    uses: e0da/actions/.github/workflows/pr-quality.yml@main
    with:
      runner: puck-linux-arm64
      projection-label: approved[pr-reviewer]
```

The review helper publishes the structured native review before it adds that
review's URL to the PR body, so one helper invocation emits two events. No
declared review, body, or commit event conditionally skips the authoritative
job, so any job that reports success executed the gate against current GitHub
state. The per-PR concurrency group permits one running job and the newest
pending job; GitHub may replace an older pending event, but it does not cancel
the allocated runner. This lets the paired helper events converge on live state
without leaving a canceled ARC job in progress.

The stable displayed check is `PR Quality / Adversarial Review`. Make that
check required in branch protection for Graphite-managed repositories.

Both the caller and reusable job require `issues: write` and
`pull-requests: write` for PR label projection. Reusable workflows can maintain
or reduce caller permissions but cannot elevate them, so both declarations must
carry the contract. The gate does not check out or execute pull-request code.
Forked contributions with a read-only token require a separately designed
trusted metadata broker; do not switch this workflow to `pull_request_target`
as an implicit workaround.

The selected runner must provide verified `gh` and `jq` commands plus either
`sha256sum` or `shasum`; its `gh api` implementation must support the standard
`--paginate` and `--jq` options. Review items are streamed and assembled with
`jq -s`, so the workflow does not require `gh api --slurp`. The gate fails
closed when these capabilities are absent and never downloads tools at runtime.
The SAMOS Puck runner image owns this baseline. Other runner profiles must make
the same capability explicit.

## Actions self-proof

`.github/workflows/pr-quality-self.yml` owns PR body and native-review events in
`e0da/actions` and calls the branch-local reusable workflow. Both the source
repository and consumers therefore render the stable check
`PR Quality / Adversarial Review` without causing broad self-CI to rerun on
metadata-only edits.

`tests/pr_quality.sh` provides offline contract fixtures for valid independent
and reduced-assurance receipts plus poison, missing-section, comment-only,
hidden-comment, fenced-code, stale, malformed, foreign, changes-requested,
unresolved, digest-mismatch, duplicate-receipt, metadata-tamper,
repository/PR-binding, review-supersession, pagination, and head-race failures.
`tests/pr_quality_helper.sh` covers canonical `$rvw` input, review reuse,
concurrent PR changes, and recovery after a partial publish/PATCH failure.
