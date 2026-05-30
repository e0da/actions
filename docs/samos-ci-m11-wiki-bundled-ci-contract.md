# SAMOS CI M11 Wiki Bundled CI Contract

Linear:
[E0D-1126](https://linear.app/e0da/issue/E0D-1126/actionswiki-design-bundled-wiki-ci-workflow-contract).

Parent:
[E0D-1125](https://linear.app/e0da/issue/E0D-1125/m11-s1-bundled-wiki-ci-workflow-shape-proof).

Status: design contract for the implementation slice. No source workflow
behavior is changed by this document.

## Value Thread

Core pillar: keep Puck CI fast, reviewable, and rollback-safe while preserving
trust in hosted checks.

Periodic focus: reduce wiki normal PR CI fanout before adding more runner
capacity.

Immediate deliverable: define one reusable `actions` workflow contract that lets
`wiki` run the same health checks with fewer macOS jobs.

Persona story: As the Agency operator, I can review a concrete workflow contract
before implementation so that the next CI change reduces wiki queue pressure
without hiding required evidence, mutating runner topology, or touching deploy.

## Current Wiki CI Surface

The current `e0da/wiki` CI source calls five reusable workflows from
`.github/workflows/ci.yml`:

| Caller job | Reusable workflow | Event behavior | Current runner input | Expanded check surface |
| --- | --- | --- | --- | --- |
| `approval-gate` | `approval-gate.yml` | Pull requests only | `puck-macos-arm64` | `approval-gate / Approval Report` |
| `hosted-drift` | `hosted-drift-report.yml` | Pull requests and manual dispatch | `puck-macos-arm64` | `hosted-drift / Hosted runner drift report` |
| `baseline` | `ci-baseline.yml` | Pull requests and manual dispatch | `puck-macos-arm64` | `baseline / PR Title (Conventional Commits)`, `baseline / Secret Scan (Gitleaks)` |
| `markdown` | `ci-markdown.yml` | Pull requests and manual dispatch | `puck-macos-arm64` | `markdown / Broken Link Check`, `markdown / YAML Frontmatter Validation` |
| `jekyll` | `ci-jekyll.yml` | Pull requests and manual dispatch | `puck-macos-arm64` | `jekyll / Jekyll` |

Normal pull request CI therefore expands to seven macOS jobs on the one
repo-scoped wiki runner. Manual dispatch skips the approval report and PR-title
check, but still fans out the remaining health checks.

GitHub branch protection is not configured for `wiki` `main`, and the repository
has no active rulesets. The preservation target is therefore the reviewer-facing
check evidence, not a GitHub-required status-check list.

The current repo-scoped runner is:

| Runner | OS | Labels |
| --- | --- | --- |
| `puck` | macOS ARM64 | `self-hosted`, `macOS`, `ARM64`, `puck`, `macos-arm64`, `puck-macos-arm64` |

The M9 baseline remains the comparison point:

| Metric | Baseline |
| --- | ---: |
| Wiki CI queue p90 | 105s |
| Wiki CI successful-run-only queue p90 | 107s |
| Wiki CI execution p90 | 60s |
| Wiki deploy queue p90 | 4s |
| Wiki deploy execution p90 | 29s |

## Proposed Reusable Workflow

Add a reusable workflow in this repository:

```text
.github/workflows/ci-wiki-bundled.yml
```

The workflow should expose one job named `Wiki CI`. That job should run the
current approval report, hosted drift report, baseline, markdown, and Jekyll
checks as named steps in one runner allocation.

Initial caller shape in `e0da/wiki`:

```yaml
jobs:
  wiki-ci:
    uses: e0da/actions/.github/workflows/ci-wiki-bundled.yml@main
    with:
      runner: puck-macos-arm64
      hosted-drift-mode: enforce
      approval-labels: approved[agency]
      link-args: >-
        --verbose
        --no-progress
        --config .lychee.toml
        --root-dir .
        './**/*.md'
      test-command: bash tests/wiki_ia_test.sh
    secrets: inherit
```

Initial workflow-call inputs:

| Input | Type | Default | Purpose |
| --- | --- | --- | --- |
| `runner` | string | `ubuntu-latest` | Runner label for the bundled job. `wiki` passes `puck-macos-arm64`. |
| `runner-profile` | string | empty | Existing runner profile metadata; validation only. |
| `runner-capabilities` | string | empty | Existing runner capability metadata; validation only. |
| `runner-manifest` | string | empty | Optional manifest used by markdown runner validation. |
| `tool-mode` | string | `workflow-install` | Existing markdown link-check tool setup mode. |
| `link-args` | string | current `ci-markdown.yml` default | Arguments passed to `lychee`. |
| `ruby-version` | string | `3.2` | Ruby version used by the Jekyll and frontmatter steps. |
| `build-command` | string | `bundle exec jekyll build --strict_front_matter` | Jekyll build command. |
| `test-command` | string | empty | Caller-specific post-build test command. |
| `hosted-drift-mode` | string | `report` | Existing hosted drift policy mode; `wiki` passes `enforce`. |
| `hosted-drift-allowlist-path` | string | `.github/samos-hosted-runner-allowlist.tsv` | Existing hosted-drift allowlist path. |
| `approval-labels` | string | `approved[agency]` | Labels reported as Agency approval evidence. |
| `approval-report` | boolean | `true` | Emit the advisory approval report on pull requests. |

The implementation should keep invalid workflow inputs and setup failures as
real CI failures. Missing approval evidence remains advisory and exits zero.
Gitleaks findings must also preserve the current `ci-baseline.yml` advisory
behavior: scan findings are reported without making CI red, while Gitleaks
download, checksum, install, or runner setup failures remain real failures.

## Step Contract

The single job should run these named steps:

1. Validate runner contract.
2. Check out the caller repository with full history for Gitleaks.
3. Approval report, only when `approval-report` is true and the event is
   `pull_request`.
4. PR title validation, only when the event is `pull_request`.
5. Hosted runner drift scan.
6. Install and run Gitleaks.
7. Install or validate `lychee`, according to `tool-mode`.
8. Broken link check.
9. Set up Ruby and Bundler.
10. YAML frontmatter validation.
11. Install `ripgrep` if needed.
12. Jekyll build.
13. Caller `test-command`, when configured.

This reduces normal wiki pull request fanout from seven macOS jobs to one macOS
job. Manual dispatch fanout drops from the current health-check set to one job.

## Review Visibility

The bundled workflow trades several GitHub job contexts for one job context with
named steps. That is acceptable for M11 because `wiki` has no branch-protection
required status contexts today, and Agency merge authority reads approval labels
directly rather than relying on CI to block missing approval.

The implementation should preserve review visibility by:

- using stable, descriptive step names matching the current check categories;
- writing a step summary table with `pass`, `fail`, `skipped`, or `advisory` for
  approval, hosted drift, PR title, secret scan, broken links, frontmatter,
  Jekyll build, and IA test;
- failing the job at the first blocking health-check failure after the failing
  step has emitted a clear annotation or log line;
- keeping missing approval evidence and Gitleaks findings advisory, matching the
  current approval report and `ci-baseline.yml` semantics;
- documenting any deliberate coverage change in the implementation PR body.

The implementation should not remove the old reusable workflows. They remain
shared building blocks and rollback targets.

## Rollback

Caller rollback is one file revert in `e0da/wiki`:

1. Restore the current five-call CI shape: `approval-gate`, `hosted-drift`,
   `baseline`, `markdown`, and `jekyll`.
2. Keep `deploy.yml` unchanged.
3. Verify wiki PR CI and wiki deploy after rollback.

Shared workflow rollback:

1. Remove `.github/workflows/ci-wiki-bundled.yml` if it has no remaining
   callers.
2. Leave the existing reusable workflows intact.

No runner registration, runner label, host service, Docker, cache, artifact,
branch-protection, or deploy rollback is required.

## Measurement Command

Use the same Ops report window as the M9 baseline:

```sh
cd /Users/bug/src/ops
bin/actions-runner-inventory \
  --repo wiki \
  --include-jobs \
  --job-runs 50 \
  --summary-md /tmp/e0d-1128-wiki-post.md \
  > /tmp/e0d-1128-wiki-post.json
```

For the successful CI-only comparison, derive the same percentile shape from
the JSON:

```sh
ruby -rjson -e '
  def percentile(values, percentile)
    return nil if values.empty?
    values = values.compact.sort
    values[[((percentile / 100.0) * values.length).ceil - 1, 0].max]
  end

  report = JSON.parse(File.read(ARGV.fetch(0)))
  jobs = report.dig("repositories", "wiki", "recent_jobs").select do |job|
    job["workflow"] == "CI" &&
      job["runner_substrate"] == "self-hosted" &&
      job["run_conclusion"] == "success" &&
      job["queue_seconds"] &&
      job["execution_seconds"]
  end

  runs = jobs.group_by { |job| job["run_id"] }
  puts "successful_ci_self_hosted_jobs=#{jobs.length}"
  puts "successful_ci_runs=#{runs.length}"
  puts "queue_p90=#{percentile(jobs.map { |job| job["queue_seconds"] }, 90)}"
  puts "execution_p90=#{percentile(jobs.map { |job| job["execution_seconds"] }, 90)}"
  puts "self_hosted_jobs_per_run=#{runs.transform_values(&:length).values.sort.join(",")}"
' /tmp/e0d-1128-wiki-post.json
```

The implementation/adoption closeout should compare:

| Metric | Compare against |
| --- | --- |
| Wiki CI self-hosted jobs per normal PR run | Current seven-job PR surface |
| Wiki CI queue p90 | M9 baseline 105s |
| Wiki CI successful-run-only queue p90 | M9 baseline 107s |
| Wiki CI execution p90 | M9 baseline 60s |
| Wiki deploy queue p90 | M9 baseline 4s |
| Wiki deploy execution p90 | M9 baseline 29s |

## Non-Goals

- Do not change `e0da/wiki` deploy.
- Do not change runner labels, runner registration, or host-local services.
- Do not make approval labels a failing CI gate.
- Do not remove the existing reusable workflows in this slice.
- Do not claim host capacity is solved; this proof is about workflow demand on
  the current wiki macOS runner lane.
