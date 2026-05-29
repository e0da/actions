# SAMOS CI M10 Approval Report Contract

**Linear:** E0D-1120, E0D-1123, E0D-1129

**Status:** superseded on 2026-05-29. The reusable workflow remains available as
an advisory approval report, not as a CI merge gate.

## Purpose

The approval report observes live GitHub approval signals without turning
approval state into CI health. It exists to keep reviewer and merge-authority
context visible while avoiding the chicken-and-egg where CI is red until an
approval label exists, and reviewers cannot treat CI as green until CI passes.

## Value Thread

As an Agency technical lead, I can read GitHub Actions as build/test health and
read `approved[...]` labels as merge-authority intent so that review, approval,
and Graphite merge decisions stay separate.

This supports Puck CI Performance Optimization by preventing policy-only
failures from polluting runner-capacity evidence. It also supports trustworthy
autonomous delivery by keeping approval discipline in the Agency review loop.

## Contract

The workflow reports these live PR signals:

| Signal | Source | Meaning |
| --- | --- | --- |
| Code review | GitHub PR review state | At least one current review state is `APPROVED`. |
| Agent approval | GitHub PR labels | At least one PR label is both syntactically an `approved[...]` label and present in the configured allowed label list. |

The workflow ignores:

- issue comments;
- review comments;
- PR body text;
- commit messages;
- branch names;
- check-run names or output;
- labels that contain approval-looking text but are not exact label names;
- `approved[...]` labels that are not in the configured allowed list.

Missing approval evidence is reported as missing merge approval and exits 0.
Agency merge authority must block merge until a clean review record and accepted
approval signal exist.

## Failure Semantics

The approval report must not fail CI because approval evidence is absent.

It may still fail for workflow or infrastructure errors, including:

- invalid input values;
- invalid configured approval label syntax;
- GitHub API or `gh` invocation failures while querying PR state;
- runner setup failures such as an unavailable GitHub CLI install.

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

Matching the shape is necessary but not sufficient. The workflow only reports
labels that are explicitly configured through `allowed-labels`.

Recommended label metadata:

| Field | Value |
| --- | --- |
| Name | `approved[agency]` |
| Description | `Approved by agency merge authority` |
| Color | `0E8A16` |

## Workflow Shape

The workflow remains at:

```text
.github/workflows/approval-gate.yml
```

The filename is retained for compatibility with existing callers. Its semantics
are advisory.

Optional caller shape for report-only visibility:

```yaml
jobs:
  approval-report:
    uses: e0da/actions/.github/workflows/approval-gate.yml@main
    permissions:
      contents: read
      pull-requests: read
      issues: read
    with:
      allowed-labels: approved[agency]
```

Do not make this job a required status check. Do not treat its success as merge
approval.

## Inputs

| Input | Type | Default | Meaning |
| --- | --- | --- | --- |
| `runner` | string | `puck-linux-arm64` | Runner label used by the report job. |
| `allowed-labels` | string | `approved[agency]` | Comma- or newline-delimited exact approval labels to report. |
| `require-pr-event` | boolean | `true` | Deprecated compatibility input. Non-PR events always skip successfully. |
| `report-mode` | string | `summary` | Human-readable output mode. It does not change exit status for missing approval. |

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

No write permission is required. The workflow observes approval state; it does
not create labels, post comments, mutate PR metadata, merge PRs, or change branch
protection.

## Merge Authority Boundary

Approval enforcement belongs outside CI:

1. review the PR and fix blocking findings;
2. verify CI/build/test evidence;
3. add the appropriate `approved[...]` label when the repo uses approval labels;
4. run `gt merge --dry-run` from the intended branch;
5. merge through `gt merge` only when Agency merge authority is active and the
   review record is clean.

This workflow can provide supporting visibility for step 3, but it is not the
step 3 enforcement mechanism.

## Acceptance Checklist

- Missing approval exits 0 and reports that merge authority must block merge.
- Real GitHub `APPROVED` reviews are reported.
- Real allowed `approved[...]` PR labels are reported.
- Comment-only approvals do not count.
- Allowed labels are exact configured names, not every syntactically valid
  `approved[...]` label.
- Required permissions are `contents: read`, `pull-requests: read`, and
  `issues: read`.
- No E0DA repo should add this workflow as a required status check.
