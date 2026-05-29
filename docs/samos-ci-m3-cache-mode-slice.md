# SAMOS CI M3 Cache-Mode Slice

Date: 2026-05-29

Linear: E0D-1049

## Scope

This is the M3-S1 implementation design for the first shared CI policy knob
after the Puck runner baseline work. It chooses a narrow `cache-mode` slice for
the reusable Elixir workflow:

- `.github/workflows/ci-elixir.yml`

The design is intentionally smaller than the full policy vocabulary. It is an
implementation-ready slice for `E0D-1050`, not a broad rewrite of CI.

## Current Evidence

The fresh timing report from `E0D-1048` inspected 380 jobs across a 20-run
window per active SAMOS repository:

| Metric | Value |
| --- | ---: |
| Self-hosted jobs | 291 |
| GitHub-hosted jobs | 45 |
| Not-run jobs | 44 |
| Unknown-substrate jobs | 0 |
| Dominant recent delay | queue |
| Overall queue p90 | 87s |

By runner profile:

| Substrate | Runner profile | Jobs | Queue p50 | Queue p90 | Execution p50 | Execution p90 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| self-hosted | `puck` | 80 | 62s | 104s | 12s | 59s |
| self-hosted | `puck-linux-arm64` | 211 | 12s | 83s | 10s | 30s |
| github-hosted | `github-hosted` | 1 | 2s | 2s | 70s | 70s |
| github-hosted | `ubuntu-latest` | 44 | 2s | 3s | 7s | 31s |

This means M3 policy work must not claim wall-clock improvement unless queue
and execution are measured separately. The queue signal is now strong enough to
justify a later capacity strategy, but `E0D-1050` should still deliver one
small additive shared policy knob because that is the groomed M3-S1 work.

## Active Caller Inventory

Two active SAMOS repos have local Elixir/Mix CI jobs that are close enough to
move behind the shared `ci-elixir.yml` reusable:

| Repo | Current shape | Cache behavior | Evidence |
| --- | --- | --- | --- |
| `mcog` | Local `mix` job on `[self-hosted, puck-linux-arm64]`; checks BEAM, installs Hex/Rebar, restores cache, runs `mix deps.get`, then `mix ci`. | `actions/cache@v4` for `deps` and `_build`, keyed by runner OS, OTP 27, Elixir 1.18.4, and `mix.lock`. | `../mcog/.github/workflows/ci.yml` |
| `symphonic` | Local `mix` job on `[self-hosted, puck-linux-arm64]`; checks BEAM, installs Hex/Rebar, restores cache, runs `mix deps.get --only test`, then `mix ci`. | `actions/cache@v5` for `deps` and `_build`, keyed by runner OS, OTP 28, Elixir 1.19.5, and `mix.lock`. | `../symphonic/.github/workflows/ci.yml` |

The shared `ci-elixir.yml` already has matching inputs for runner, OTP,
Elixir, dependency command, and CI command. It also already uses
`actions/cache@v5` for `deps` and `_build`.

The caller migration proof must treat BEAM setup as an equivalence check, not
as invisible plumbing. The local caller jobs currently inspect the runner BEAM
toolchain and install Hex/Rebar directly; the shared workflow uses
`erlef/setup-beam@v1`. That is acceptable for the implementation design, but
`E0D-1051` must record observed `erl`, `elixir`, and `mix` versions plus the
setup step output before treating the caller migration as behavior-preserving.

## Decision

Implement `cache-mode` first, on `ci-elixir.yml`.

Initial supported values:

| Value | Behavior |
| --- | --- |
| `read-write` | Restore and save the existing `deps` and `_build` Actions cache. This is the default and preserves current shared workflow behavior. |
| `off` | Skip the Actions cache step entirely. This is opt-in and allows a caller to measure whether remote cache restore/save is helping or hurting on a stable self-hosted runner. |

Unknown values must fail early with a clear message.

Deferred values:

| Value | Reason deferred |
| --- | --- |
| `read-only` | Do not add until the cache action contract for restore-only behavior is explicitly verified and tested. |
| `toolchain` | Do not add until BEAM toolchain installation or runner-image ownership is part of the slice. |
| cache-key reshaping | Do not add architecture/profile keys until mixed X64/ARM64 usage proves collisions or misses. |
| workspace persistence | Do not weaken checkout cleaning in this slice; persistent workspace state needs a separate `clean-mode` risk model. |

## Why This Beats Alternatives Now

`tool-mode` is not the next first knob because Markdown already has a proven
`tool-mode`, while Gitleaks and OpenTofu remain deferred until binary
version/hash and plugin/cache lifecycle ownership exist.

`artifact-mode` is not the next first knob because active artifact behavior is
deploy/release-specific. The wiki static-bind deploy artifact is required
deploy input, not an avoidable CI diagnostic bundle.

`clean-mode` is not the next first knob because the deploy cleanup surface mixes
safety cleanup with performance cleanup. Skipping checkout cleaning or rsync
delete may be useful later, but it has higher correctness risk than exposing
cache behavior.

`cache-mode` is the smallest useful next knob because:

- it is additive and can preserve existing behavior with `read-write`;
- it applies to an existing reusable workflow rather than inventing a new one;
- two active SAMOS repos already have nearly matching local cache behavior;
- it creates a controlled experiment surface for cache-on versus cache-off
  without runner mutation.

## Compatibility Contract

- Keep `runner` defaulting to `ubuntu-latest`.
- Keep `otp-version`, `elixir-version`, `deps-command`, and `ci-command`
  behavior unchanged.
- Add `cache-mode` as an optional string input with default `read-write`.
- Existing callers that do not set `cache-mode` must see the same behavior as
  today.
- `cache-mode: off` must only skip the cache step; it must not skip checkout,
  setup-beam, dependency installation, or CI.
- Do not change cache keys in the first implementation.
- Do not mutate runner images, runner state, or live cache storage.

## Caller Adoption Order

1. `mcog`: replace the local `mix` job with `ci-elixir.yml@main` after
   `E0D-1050` merges. Use `runner: puck-linux-arm64`,
   `otp-version: 27`, `elixir-version: 1.18.4`,
   `deps-command: mix deps.get`, `ci-command: mix ci`, and
   `cache-mode: read-write` for the behavior-preserving proof.
2. `symphonic`: replace the local `mix` job with `ci-elixir.yml@main`. Use
   `runner: puck-linux-arm64`, `otp-version: 28`,
   `elixir-version: 1.19.5`,
   `deps-command: mix deps.get --only test`, `ci-command: mix ci`, and
   `cache-mode: read-write` for the behavior-preserving proof.

If either caller proof has acceptable behavior-preserving timing, a follow-up
experiment may compare `cache-mode: off` on the same caller. Do not combine the
behavior-preserving migration and cache-off experiment in one PR.

## E0D-1050 Implementation Plan

1. Add `cache-mode` input to `.github/workflows/ci-elixir.yml` with default
   `read-write`.
2. Add an early validation step accepting only `read-write` and `off`.
3. Gate the existing `actions/cache@v5` step with
   `if: inputs.cache-mode == 'read-write'`.
4. Keep the existing cache path, key, and restore keys unchanged.
5. Update `docs/samos-ci-performance-inventory.md` or this design doc only if
   the implementation exposes a detail not captured here.

## Verification

Local verification for `E0D-1050`:

```sh
git diff --check
actionlint .github/workflows/ci-elixir.yml
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci-elixir.yml"); puts "ok"'
```

Caller proof for `E0D-1051` must record:

- caller repo and branch
- called `e0da/actions` ref
- `runner`, OTP version, Elixir version, deps command, CI command, and
  `cache-mode`
- observed `erl`, `elixir`, and `mix` versions plus setup-beam output
- run URL and conclusion
- job URL, runner name, labels, queue duration, and execution duration
- whether the migration was behavior-preserving or a cache-off experiment

## Rollback

The shared workflow rollback is to remove the `cache-mode` input and cache-step
condition, restoring unconditional cache behavior.

Caller rollback is to restore the local `mix` job. This is straightforward
because `E0D-1051` should migrate one caller per PR and should not combine
caller migration with cache-off experimentation.

## Non-Goals

- No deploy workflow changes.
- No artifact-mode implementation.
- No Gitleaks or OpenTofu `tool-mode`.
- No cache deletion or live runner mutation.
- No checkout `clean: false` or persistent workspace policy.
- No inactive/reference repo adoption.
