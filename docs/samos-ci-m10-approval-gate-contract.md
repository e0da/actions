# SAMOS CI M10 Approval Gate Contract

**Linear:** E0D-1120

**Status:** design contract; no workflow implementation in this slice.

## Purpose

The approval gate is an opt-in CI governance check for repositories that want
merge readiness to include an explicit approval provenance signal.

It exists because same-account agents cannot reliably use GitHub's normal
approval review mechanism: GitHub does not let an account approve its own pull
request, and using separate puppet accounts or switching git identities is
operationally riskier than the current E0DA workflow should accept.

The gate gives opted-in repositories two valid approval paths:

1. a real GitHub pull request review with state `APPROVED`; or
2. a real GitHub pull request label matching an allowed `approved[...]` label.

Timeline comments, review comments, PR body text, commit messages, branch names,
and check output do not satisfy the label path. A comment containing
`approved[agency]` is still only a comment.

## Scope

In scope:

- reusable workflow contract in `e0da/actions`;
- caller-side opt-in from current living repositories only;
- aggregate-readable approval provenance through real GitHub labels;
- compatibility with normal GitHub code review when a real `APPROVED` review is
  present.

Out of scope:

- global default enablement;
- puppet GitHub accounts;
- git identity switching;
- comment-text approval fallbacks;
- rollout to dead, paused, reference-only, or prior-art repositories;
- branch-protection mutation before the gate has passed in each caller repo.

## Pass And Fail Semantics

The gate passes when at least one of these is true:

| Signal | Required source | Notes |
| --- | --- | --- |
| Code review | GitHub PR review state | At least one current review state is `APPROVED` according to GitHub review data. |
| Agent approval | GitHub PR labels | At least one PR label is both syntactically an `approved[...]` label and present in the caller's configured allowed label list. |

The gate fails when neither signal is present.

The gate must ignore:

- issue comments;
- review comments;
- PR body text;
- commit messages;
- check-run names or output;
- labels that contain approval-looking text but are not exact label names;
- `approved[...]` labels that are not in the caller's configured allowed list.

If both approval paths are present, the gate should pass and report both paths.
The first implementation should not try to decide which approval path is more
authoritative.

## Label Contract

Allowed approval labels must match this shape:

```text
approved[<approver-id>]
```

Where `<approver-id>` is limited to ASCII letters, digits, dot, underscore, and
hyphen:

```text
^approved\[[A-Za-z0-9._-]+\]$
```

Matching the shape is necessary but not sufficient. The caller must also
configure the exact label name as allowed.

Default allowed label:

```text
approved[agency]
```

The reusable workflow should accept a newline-delimited or comma-delimited
`allowed-labels` input so a repository can explicitly permit labels such as
`approved[agency]`, `approved[e0da]`, or a repo-specific agent label. The gate
must not treat every syntactically valid `approved[...]` label as approval by
default.

Recommended label metadata:

| Field | Value |
| --- | --- |
| Name | `approved[agency]` |
| Description | `Approved by agency merge authority` |
| Color | `0E8A16` |

## Reusable Workflow Shape

The future implementation should live in `e0da/actions` as a reusable workflow,
for example:

```text
.github/workflows/approval-gate.yml
```

Expected caller shape:

```yaml
jobs:
  approval-gate:
    uses: e0da/actions/.github/workflows/approval-gate.yml@main
    permissions:
      contents: read
      pull-requests: read
      issues: read
    with:
      allowed-labels: approved[agency]
```

Required inputs:

| Input | Type | Default | Meaning |
| --- | --- | --- | --- |
| `allowed-labels` | string | `approved[agency]` | Comma- or newline-delimited exact approval labels. |

Optional inputs:

| Input | Type | Default | Meaning |
| --- | --- | --- | --- |
| `require-pr-event` | boolean | `true` | Fail when the workflow is not running for a pull request. |
| `report-mode` | string | `summary` | Controls human-readable output only; it must not change pass/fail semantics. |

The first implementation should run only against pull request context. Push-only
events should either be excluded by caller workflow shape or fail clearly when
`require-pr-event` is true.

## Permissions

Caller jobs must grant:

```yaml
permissions:
  contents: read
  pull-requests: read
  issues: read
```

`pull-requests: read` is required to inspect reviews. `issues: read` is required
because GitHub pull request labels are exposed through issue/PR label APIs.
`contents: read` supports checkout-free GitHub API workflows and keeps the job
compatible with normal repository read policy.

No write permission is required for the gate. The gate observes approval state;
it does not create labels, post comments, mutate PR metadata, or change branch
protection.

## Implementation Notes

The implementation should query GitHub APIs for the live PR state instead of
parsing rendered timeline text.

Recommended behavior:

1. resolve the current pull request number from `github.event.pull_request`;
2. fetch PR labels from GitHub issue/PR label data;
3. fetch review data from GitHub pull request review data;
4. normalize configured `allowed-labels`;
5. check for an exact allowed-label match on the live PR labels;
6. check for an approved review signal from GitHub review state;
7. emit a concise summary naming which path passed or why both paths failed;
8. exit nonzero when neither path passes.

The gate should print:

- whether an `APPROVED` code review was found;
- which allowed `approved[...]` labels were found;
- which approval labels existed but were ignored because they were not allowed;
- the configured allowed label set.

The gate should not print secrets or full event payloads.

## Rollout Contract

Rollout is intentionally separate from implementation.

Before opting repositories in, E0D-1122 must classify current repositories as:

- living;
- paused/reference;
- dead/out of scope.

Only living repositories should be opted in by E0D-1123. Known dead or inactive
surfaces called out by the user, including `brain`, `heres-a-tip`, and
`Fabric`, must not be touched unless the canonical active-repo inventory says
otherwise.

For each living repository:

1. ensure the real `approved[agency]` label exists or create it with the
   recommended metadata;
2. add the reusable approval gate in a PR;
3. verify the gate passes with a real `APPROVED` review or a real allowed
   `approved[...]` label;
4. only then consider branch protection / required-check changes, if that repo
   uses required checks;
5. record which approval path was used for the rollout PR.

## Acceptance Checklist

- Pass condition is real GitHub `APPROVED` review or real allowed
  `approved[...]` PR label.
- Fail condition is neither signal present.
- Comment-only approvals do not count.
- The opt-in shape is a reusable workflow included by each caller repository.
- Allowed labels are exact configured names, not every syntactically valid
  `approved[...]` label.
- Required permissions are `contents: read`, `pull-requests: read`, and
  `issues: read`.
- The rationale explicitly avoids puppet accounts and git identity switching.
- Rollout target is current living projects only after inventory.
