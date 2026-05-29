# SAMOS CI M5 Artifact Hop Slice

Linear:
[E0D-1068](https://linear.app/e0da/issue/E0D-1068/actionswiki-design-reversible-deploy-artifact-hop-policy-slice).

Parent:
[E0D-1066](https://linear.app/e0da/issue/E0D-1066/m5-s1-storage-and-artifact-control-plane-reduction-proof).

## Goal

Design the smallest reversible M5-S1 source change for artifact storage and
control-plane overhead after M4 removed duplicate wiki main CI from the deploy
path.

The target is wiki deploy. The refreshed E0D-1067 inventory found `wiki-site`
is still the dominant active artifact family:

- 109 returned `wiki-site` artifacts;
- 419.43 MiB returned `wiki-site` bytes;
- 88.21 MiB active `wiki-site` bytes;
- 88 expired `wiki-site` records returned by the API;
- latest active artifact expires at 2026-05-30T10:13:33Z.

## Source Facts

`wiki/.github/workflows/deploy.yml` is a two-job static-bind deployment:

1. `build` runs on `[self-hosted, puck]`.
2. It builds the Jekyll site with `tests/wiki_ia_test.sh`.
3. It uploads `_site/` as the `wiki-site` artifact with `retention-days: 1`.
4. `deploy` calls `e0da/actions/.github/workflows/deploy-compose.yml@main`.
5. The reusable workflow downloads `wiki-site` and rsyncs it to
   `/Users/e0da/.wiki-site`.

`actions/.github/workflows/deploy-compose.yml` implements ADR-016 archetype A
as an artifact-consuming static-bind deploy:

- archetype A requires `artifact-name` and `bind-target`;
- `actions/download-artifact@v8` downloads the artifact into `_artifact`;
- the deploy step rsyncs `_artifact/${artifact-source-dir}` to the bind target;
- non-A archetypes refresh the stack working tree, but archetype A does not.

## Options

| Option | Result | Risk | Decision |
| --- | --- | --- | --- |
| Retention-only | Keep current architecture and set retention lower than 1 day. | Too-short retention can break delayed deploy reruns; current retention is already 1 day. | Reject for M5-S1. |
| Generic `artifact-mode` input in `deploy-compose.yml` | Add shared policy before a second active static-bind caller needs it. | Premature abstraction; reusable job cannot see the caller build workspace without a transfer contract. | Defer. |
| Direct Puck-local handoff through a long-lived path | Build `_site` in one job and pass an absolute runner workspace path to another job. | Unsafe across runners and reruns; depends on ephemeral workspace layout. | Reject. |
| Diagnostics-only cleanup | Audit SARIF or logs artifacts. | Much smaller than `wiki-site`; does not address the dominant active family. | Defer. |
| Wiki-only single-job static-bind deploy | Build and rsync `_site/` in one Puck job, no Actions artifact. | Bypasses the shared archetype-A reusable for this one static site. | Select. |

## Selected Design

Implement a wiki-only single-job static-bind deploy:

1. Keep the trigger shape unchanged: `push` to `main` and `workflow_dispatch`.
2. Keep the runner unchanged: `[self-hosted, puck]`.
3. Checkout the wiki repository.
4. Build and assert IA with the existing Jekyll command.
5. Rsync `_site/` directly to `/Users/e0da/.wiki-site`.
6. Do not upload `wiki-site`.
7. Do not call `deploy-compose.yml` for wiki.

This removes the artifact upload/download hop for wiki deploy while preserving
the important rerun behavior: rerunning the deploy workflow rebuilds the site
from the same commit and deploys that output. It does not preserve the narrower
ability to rerun only the deploy job against a previously uploaded artifact,
but that behavior currently exists only inside a 1-day artifact window and is
not the stronger contract for wiki. The stronger contract is "deploy this wiki
commit", which a single rebuild-and-rsync job preserves.

Review gate: if deploy-job-only reruns from a previously uploaded artifact are
declared mandatory for wiki, fall back to the conservative guard-only design:
add an `artifact-mode` input to `deploy-compose.yml`, default it to
`deploy-input`, require that mode for archetype A, and make unsupported values
such as `off` or `local-handoff` fail with a clear message. That fallback makes
the policy explicit but does not reduce storage or artifact-hop time.

## Why Not A Shared `artifact-mode` Yet

`artifact-mode` still belongs in the shared policy vocabulary, but not as the
first M5-S1 implementation. Release artifacts and archetype-A deploy artifacts
have different safety contracts:

- release artifacts feed GitHub Release publication and must remain preserved;
- static-bind deploy artifacts feed Puck rsync and can sometimes be replaced by
  same-job output;
- validation artifacts should remain logs-only unless diagnostics are requested.

Adding a shared knob now would likely encode "skip artifact" before enough
callers exist to define a safe replacement contract. The wiki-only path proves
whether removing this hop actually reduces storage/control-plane overhead first.

## Rollback

Rollback is source-only in `wiki`:

1. Restore the two-job `build` plus `deploy` workflow.
2. Restore the `actions/upload-artifact@v7` step with `name: wiki-site`,
   `path: _site/`, `if-no-files-found: error`, and `retention-days: 1`.
3. Restore the reusable `deploy-compose.yml` call with archetype A,
   `artifact-name: wiki-site`, `artifact-source-dir: "."`, and
   `bind-target: /Users/e0da/.wiki-site`.

No live runner, stack, DNS, Caddy, Docker, cache, or artifact deletion rollback
is required because the selected change is source-only.

## Stop Conditions

- Do not proceed if wiki maintainers require the ability to rerun only the
  deploy job from a previously uploaded artifact; use the guard-only fallback
  instead.
- Do not proceed if branch protection or deploy audit policy requires the
  reusable `deploy-compose.yml` job for wiki.
- Do not proceed if the single-job deploy cannot preserve the existing IA build
  gate before rsync.
- Do not delete existing artifacts or caches as part of this slice.
- Do not alter release artifact behavior.
- Do not make a generic `artifact-mode` knob until a second caller needs the
  same contract or wiki proof shows this approach works.

## Proof Plan

The implementation issue should prove:

- PR CI succeeds for wiki.
- The merged wiki deploy run has no `Upload site artifact` step.
- The merged wiki deploy run has no `actions/download-artifact` step.
- The merged wiki deploy run rsyncs `_site/` to `/Users/e0da/.wiki-site`.
- The Puck-served wiki route returns the new page after deploy.
- A post-change storage inventory shows no new `wiki-site` artifact for the
  implementation merge run.
- Queue, execution, and storage are reported separately.
