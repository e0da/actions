# SAMOS CI M6 Hosted Drift Contract

Linear:
[E0D-1074](https://linear.app/e0da/issue/E0D-1074/actions-design-hosted-drift-allowlist-and-enforcement-contract).

Parent:
[E0D-1072](https://linear.app/e0da/issue/E0D-1072/m6-s1-hosted-runner-drift-inventory-and-enforcement-contract).

## Goal

Design the smallest additive contract for hosted-runner drift enforcement after
the E0D-1073 inventory.

The inventory result is important:

- current active SAMOS source does not show unapproved direct hosted routing;
- the 30-run API window still contains 78 GitHub-hosted jobs, but those are
  historical observations from older `symphonic`, `mcog`, and `stack` runs;
- shared reusable workflows intentionally retain `ubuntu-latest` compatibility
  defaults for non-SAMOS callers;
- active SAMOS callers now route to Puck with explicit runner overrides or
  direct self-hosted labels.

M6 should therefore prevent future active caller drift without converting
compatibility defaults into breaking changes.

## Definitions

| Term | Meaning | Enforcement treatment |
| --- | --- | --- |
| Direct Puck routing | The caller uses `[self-hosted, ...]`, `puck`, `puck-linux-arm64`, or `puck-macos-arm64`, either directly or via a reusable workflow input. | Allowed. |
| Compatibility default | A reusable workflow in `actions` keeps a hosted default such as `ubuntu-latest` while callers may override it. | Allowed by default. |
| Approved hosted fallback | A current active SAMOS caller intentionally uses hosted compute for a documented capability gap. | Allowed only with explicit metadata. |
| Historical hosted observation | GitHub API job data records hosted jobs from older runs, but current source no longer routes there. | Not drift. |
| Active hosted drift | Current active SAMOS source routes CI/release/deploy work to hosted compute without approved fallback metadata. | Report now; block after proof. |
| Unknown | The checker cannot confidently classify a source or job record. | Report and require human review before blocking. |

## Source Facts

Active SAMOS callers are `actions`, `ops`, `stack`, `mcog`, `symphonic`, and
`wiki`.

Current active caller routing:

| Repo | Source shape | Classification |
| --- | --- | --- |
| `actions` | Puck smoke runs on `[self-hosted, puck-linux-arm64]`; deploy compose runs on `[self-hosted, puck]`. | Direct Puck routing. |
| `ops` | `ci-baseline.yml` and `ci-opentofu.yml` are called with `runner: puck-linux-arm64`. | Direct Puck routing. |
| `stack` | Baseline and Markdown calls pass `runner: puck-linux-arm64`; local worker and shellcheck jobs use self-hosted Puck labels. | Direct Puck routing. |
| `mcog` | Baseline and Elixir calls pass `runner: puck-linux-arm64`; deploy image build runs on self-hosted Puck Linux. | Direct Puck routing. |
| `symphonic` | Baseline and Elixir calls pass `runner: puck-linux-arm64`; release validate, image, and publish run on self-hosted Puck Linux. | Direct Puck routing. |
| `wiki` | Baseline, Markdown, and Jekyll calls pass `runner: puck-macos-arm64`; deploy runs on `[self-hosted, puck]`. | Direct Puck routing. |

Reusable workflow hosted defaults remain intentional compatibility surface:

- `ci-baseline.yml`
- `ci-bats.yml`
- `ci-elixir.yml`
- `ci-jekyll.yml`
- `ci-markdown.yml`
- `ci-opentofu.yml`
- `ci-rust.yml`
- `ci-typescript-bun.yml`
- `release-rust.yml`

`deploy-compose.yml` is Puck-only and is not a hosted-default workflow.

## Decision

Use caller-side report-only detection as the first source change.

The first M6 implementation should add a reusable report workflow in `actions`
that active SAMOS repos can call from their own CI. It should inspect the
caller's checked-out `.github/workflows` files and produce a hosted-drift report
without failing the run.

Initial workflow name:

```text
.github/workflows/hosted-drift-report.yml
```

Initial mode input:

| Input | Default | Meaning |
| --- | --- | --- |
| `mode` | `report` | `report` always exits 0 after emitting findings. `enforce` is reserved and should fail closed until a later PR enables it deliberately. |
| `runner` | `puck-linux-arm64` | Runner label for the report job. Active SAMOS callers should keep the report on Puck. |
| `allowlist-path` | `.github/samos-hosted-runner-allowlist.tsv` | Optional caller-owned fallback metadata. Missing file means no approved hosted fallbacks. |

This is deliberately caller-side. A reusable CI workflow cannot reliably know
whether a caller is an active SAMOS repo versus a public or future non-SAMOS
consumer. Caller-side adoption makes SAMOS intent explicit without changing the
existing hosted defaults.

## Report Rules

The report should classify source evidence into three buckets.

### Definite Hosted

Report these as hosted findings:

- direct `runs-on: ubuntu-latest`;
- direct `runs-on: macos-latest`;
- direct `runs-on: windows-latest`;
- direct hosted labels in flow style such as `runs-on: [ubuntu-latest]`;
- calls to `e0da/actions/.github/workflows/*.yml` that omit an explicit
  self-hosted/Puck runner override where that called workflow exposes a `runner`
  input.

### Definite Puck

Report these as Puck-routed:

- direct `runs-on` containing `self-hosted`;
- direct `runs-on` containing `puck`;
- reusable calls with `runner: puck-linux-arm64`;
- reusable calls with `runner: puck-macos-arm64`;
- `deploy-compose.yml` calls, because the reusable deploy job hard-routes to
  `[self-hosted, puck]`.

### Unknown

Report these as unknown:

- expression-only `runs-on` that does not resolve to a literal label in source;
- matrix `runs-on` values outside the known `actions/release-rust.yml` contract;
- reusable calls whose called workflow is not in `e0da/actions`;
- any YAML shape the scanner cannot classify without a real parser.

Unknown findings should not block in M6-S1. They should be visible so the
blocking policy can decide whether to require allowlist metadata later.

## Fallback Metadata

The allowlist file is intentionally simple and caller-owned:

```text
# workflow<TAB>job_or_pattern<TAB>runner<TAB>linear<TAB>expires<TAB>reason
.github/workflows/release.yml<TAB>publish<TAB>ubuntu-latest<TAB>E0D-0000<TAB>2026-06-30<TAB>documented hosted-only capability
```

Rules:

- tabs are the delimiter;
- blank lines and `#` comments are ignored;
- `linear` is required and must name the issue that approves the fallback;
- `expires` is required for hosted fallback in active SAMOS repos;
- expired allowlist entries should be reported even in `report` mode;
- M6-S1 should not require an allowlist when there are no active hosted
  findings.

The first report-only implementation may parse and display allowlist entries
without matching them perfectly to every finding. Blocking enforcement should
wait until matching semantics are proven on at least two active callers.

## Why Not Block Immediately

Blocking immediately is the wrong first step because:

- the inventory found no current active source drift to block;
- reusable hosted defaults are intentional and should not break non-SAMOS
  consumers;
- a lightweight scanner may initially report unknown YAML shapes;
- active callers should first prove the report output is stable in ordinary PR
  runs.

The first blocking gate should happen only after report-only proof shows:

- no false positives on at least two active SAMOS repos;
- approved fallback metadata is readable and reviewable;
- unknown findings are either eliminated or explicitly accepted as non-blocking;
- rollback is one-line caller removal or `mode: report`.

## Implementation Slice For E0D-1075

Recommended source change:

1. Add `.github/workflows/hosted-drift-report.yml` to `actions`.
2. Keep the job on `runner: ${{ inputs.runner }}` with default
   `puck-linux-arm64`.
3. Check out the caller repository.
4. Run a POSIX shell report script inline or from a small checked-in helper.
5. Emit a Markdown step summary with counts and findings.
6. In `mode: report`, exit 0 even when hosted findings exist.
7. In `mode: enforce`, fail with a clear message that enforcement is reserved
   until M6 proof enables it, unless the same PR explicitly implements and
   verifies enforcement.

Proof callers for E0D-1076:

1. `ops`, because its current CI already runs entirely on Puck Linux and has no
   active hosted fallback.
2. `wiki`, because it exercises Puck macOS caller overrides and the separate
   Puck deploy lane.

If either caller produces false positives that are hard to explain, keep M6-S1
report-only and use the output to refine E0D-1075 or a follow-up issue.

## Rollback

Shared workflow rollback:

1. Remove `.github/workflows/hosted-drift-report.yml`.
2. Remove any helper script added only for hosted-drift reporting.

Caller rollback:

1. Remove the report job from the caller CI workflow, or set `mode: report` if
   a later enforcement mode has been enabled.

No runner, artifact, cache, deployment, Docker, or host-local rollback is
required.

## Stop Conditions

- Do not change existing `runner` defaults in reusable CI workflows.
- Do not make compatibility defaults fail for non-SAMOS callers.
- Do not add blocking enforcement until report-only output is proven on active
  callers.
- Do not treat historical hosted API observations as active source drift.
- Do not require public forks to use self-hosted runners.
- Do not add Ruby or Python tooling for this policy.
- Do not mutate live runners, caches, artifacts, or deployment state.

## Verification Plan

Local verification for this design doc:

```sh
git diff --check
LC_ALL=C grep -n '[^ -~]' docs/samos-ci-m6-hosted-drift-contract.md || true
rg -n "E0D-1074|Decision|Implementation Slice|Stop Conditions|Verification Plan" docs/samos-ci-m6-hosted-drift-contract.md
```

Implementation verification for E0D-1075:

```sh
git diff --check
actionlint .github/workflows/hosted-drift-report.yml
sh -n <hosted-drift-report-script>
```

Caller proof for E0D-1076 must record:

- caller repo and branch;
- called `e0da/actions` ref;
- report workflow run URL and conclusion;
- runner name and labels for the report job;
- hosted, Puck, and unknown finding counts;
- whether findings are true positive, approved fallback, historical-only, or
  false positive;
- queue and execution duration for the report job.
