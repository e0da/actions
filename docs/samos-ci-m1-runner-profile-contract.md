# SAMOS CI M1 Runner-Profile Contract

Date: 2026-05-28

Linear: E0D-1020

Scope: M1-S1 under the SAMOS CI performance work. This is the smallest safe
implementation slice after
[`docs/samos-ci-performance-inventory.md`](samos-ci-performance-inventory.md):
add a runner policy vocabulary to active reusable CI workflows without changing
their runner routing, setup behavior, cache behavior, artifact behavior, or
hosted defaults.

## In Scope

Active reusable workflows for the first slice:

- `.github/workflows/ci-baseline.yml`
- `.github/workflows/ci-markdown.yml`
- `.github/workflows/ci-jekyll.yml`
- `.github/workflows/ci-opentofu.yml`

Active SAMOS caller repos for proof work remain `actions`, `ops`, `stack`,
`mcog`, `symphonic`, and `wiki`. Inactive/reference repos are not optimization
targets for this contract.

`deploy-compose.yml` is explicitly deferred to a deploy-specific slice. It has
Puck-only deploy assumptions, archetype-specific artifact handling, destructive
sync behavior, Docker credential handling, and secret cleanup policy. Do not mix
that surface into the CI runner-profile slice.

## Compatibility Contract

- Keep the raw `runner` input in every workflow.
- Keep every hosted default exactly as it is today.
- Keep `runs-on: ${{ inputs.runner }}` unchanged in the first implementation.
- Add `runner-profile` as an optional string input with default `""`.
- Add `runner-capabilities` as an optional string input with default `""`.
- Empty `runner-profile` and empty `runner-capabilities` are inert. Existing
  callers that set neither input must see the same behavior as today.
- `runner-profile` is policy metadata and validation input in this slice, not a
  replacement for `runner`.
- `runner-capabilities` is an explicit requested-capability list in this slice,
  not a hidden capability bundle implied by a profile.

This preserves the current compatibility rule from the inventory: raw runner
labels and hosted defaults remain the real scheduling contract until a later
reviewed slice proves a profile-to-runner mapping is safe.

## Initial Profiles

| Profile | Runner selection in this slice | Validation intent |
| --- | --- | --- |
| `""` | Caller uses raw `runner`; no profile validation. | Existing behavior. |
| `hosted-linux` | Caller still uses raw `runner`; default remains `ubuntu-latest`. | Job should land on Linux. |
| `puck-linux-arm64` | Caller still passes `runner: puck-linux-arm64` or a repo-specific compatible label. | Job should land on Linux ARM64. |
| `puck-macos-arm64` | Caller still passes `runner: puck-macos-arm64` or a repo-specific compatible label. | Job should land on macOS ARM64. |

Unknown non-empty profiles must fail with a clear message naming the accepted
profiles. This failure happens in a job step after GitHub schedules the job; it
does not solve queueing if the raw `runner` label cannot be matched.

## Initial Capability Tokens

`runner-capabilities` accepts a whitespace-separated token list. The first
tokens are:

| Token | Check |
| --- | --- |
| `gh` | `command -v gh` |
| `ruby` | `command -v ruby` |
| `brew` | `command -v brew` |
| `make` | `command -v make` |

Unknown requested capability tokens must fail clearly. Missing requested
capabilities must fail clearly after job scheduling, with the missing command
and token in the error. Do not require `gh` by default on Puck Linux: callers
must request `runner-capabilities: gh` only after the baseline `gh` policy is
settled.

Profile selection alone must not imply these capability checks in the first
slice. This keeps `puck-linux-arm64` usable for Markdown and OpenTofu proof work
without making the hidden baseline `gh` assumption a global Puck requirement.

## Implementation Shape

For each in-scope workflow:

1. Add the two optional inputs with empty-string defaults.
2. Add a first executable validation step to each job, before tool setup or
   checkout work.
3. Validate `runner-profile` with a shell `case` over the four initial profiles.
4. Validate profile-to-runner facts from GitHub runner context after scheduling:
   `hosted-linux` requires `runner.os == 'Linux'`; `puck-linux-arm64` requires
   `runner.os == 'Linux'` and `runner.arch == 'ARM64'`; `puck-macos-arm64`
   requires `runner.os == 'macOS'` and `runner.arch == 'ARM64'`.
5. Validate only explicitly requested capability tokens.
6. Keep all existing workflow setup paths unchanged.

The validation step should say that `runner-profile` does not choose a runner in
this slice. If queueing fails, the fix is still the caller's raw `runner` label.

Prefer POSIX-compatible shell in the validation body. The workflows currently
run shell snippets under GitHub's default Bash-compatible shell, but this
contract does not require Ruby, Python, or a new helper language for validation.

## Failure Behavior

- Empty profile and empty capabilities: no-op.
- Unknown profile: fail clearly in the validation step.
- Profile/actual runner mismatch: fail clearly in the validation step and print
  the observed `runner.os` and `runner.arch`.
- Unknown capability token: fail clearly in the validation step.
- Missing requested capability: fail clearly in the validation step.
- Unschedulable raw runner label: GitHub queueing remains the failure mode; this
  contract cannot detect it before the job starts.

## Caller Proof Order

Proof callers in this order:

1. `stack` Markdown on Linux ARM64.
2. `ops` OpenTofu on Linux ARM64.
3. `wiki` macOS Markdown and Jekyll on macOS ARM64.

Defer `mcog` and `symphonic` baseline proof until the `gh` decision is made.
Those callers exercise `ci-baseline.yml`, whose PR-title path currently tries
`gh api`; the first runner-profile slice should not accidentally turn `gh` into
a default Puck Linux requirement.

## Verification Contract

Local verification for the `actions` implementation branch:

```bash
git diff --check
actionlint .github/workflows/ci-baseline.yml .github/workflows/ci-markdown.yml .github/workflows/ci-jekyll.yml .github/workflows/ci-opentofu.yml
ruby -e 'require "yaml"; ARGV.each { |path| YAML.load_file(path); puts "ok #{path}" }' .github/workflows/ci-baseline.yml .github/workflows/ci-markdown.yml .github/workflows/ci-jekyll.yml .github/workflows/ci-opentofu.yml
```

Documentation-only verification for this contract document:

```bash
git diff --check -- docs/samos-ci-m1-runner-profile-contract.md
ruby - <<'RUBY'
path = 'docs/samos-ci-m1-runner-profile-contract.md'
base = File.dirname(path)
text = File.read(path)
missing = []
text.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each do |target|
  next if target.start_with?('http://', 'https://', '#')
  file = target.split('#', 2).first
  next if file.empty?
  resolved = File.expand_path(file, base)
  missing << target unless File.exist?(resolved)
end
abort("missing markdown links: #{missing.join(', ')}") unless missing.empty?
puts 'markdown links ok'
RUBY
```

Caller branch proof must use GitHub runs, not local reasoning alone. For each
caller proof branch, record:

- caller repo and branch
- called `e0da/actions` ref
- raw `runner`
- `runner-profile`
- `runner-capabilities`
- run URL and run conclusion
- job URL, job conclusion, runner name, labels, `runner.os`, and `runner.arch`
- queue duration and execution duration extracted from GitHub run/job metadata

## Non-Goals

- No `cache-mode` changes.
- No `artifact-mode` changes.
- No `deploy-compose.yml` changes.
- No inactive or reference repo migrations.
- No profile-to-runner replacement of raw `runner`.
- No requirement that Puck Linux provide `gh` by default.
