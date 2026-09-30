# Native agent evaluations

Pinned Promptfoo runs the matrix, repetitions, assertions, result database and viewer. This reusable suite is owned by `e0da/actions/tools/agency-eval`. It retains native trial workspaces and receipts, grades delivered source independently and permits one diagnosed repair. Personal runtime configuration and login data stay on each executing host; Ops and Stack own the durable Puck results service.

## Run and inspect

```sh
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm ci
npm test
npm run eval
npm run eval -- native --config runtime.local.json --repeat 1 --repairs 1 --timeout-ms 600000
npm run regrade -- /absolute/path/to/run/trial
npm run view
```

The default eval is an offline demonstration, clearly labeled mock; it consumes no model quota. Native mode uses the personally configured candidates. Copy runtime.example.json to runtime.local.json and replace host references; the latter stays untracked and contains no credentials. The historical commissioning snapshot had Claude logged out on Forge and an independently verified native login on CondorJF. Inspect each worker's current login; historical success does not establish current host authentication.

The viewer runs at http://127.0.0.1:15500, reading this package's .promptfoo database. The small entrypoint pins upstream TCP listeners to loopback, disables telemetry/update checks and avoids opening a browser automatically. Runs also export a standalone results.html. Sharing/cloud accounts are not used. Ctrl-C stops the viewer; it is an ordinary foreground process, not a system daemon.

## Trial semantics

Each call creates a fresh fixture and native provider instance. It saves the seed, binds the exact rendered prompt and native session, saves an immutable first snapshot/grade, and permits at most one diagnosed repair on the same failed state/session. The host grader runs 52 behavioral checks against retained source, independently of candidate tests and claimed commands. The repair uses the published contract; it does not reveal hidden oracle assertions.

Native controls use a synthetic dependency-free multi-file package, with admission state and Unicode/full-range contracts. No employer repository content is part of this suite. Client context differs: Codex uses its existing home/config and workspace-write mode, while Claude has setting_sources empty and no shell; OpenCode retains its isolated server with trial-scoped read/edit/write and no shell. These are model-plus-harness configurations, not isolated model comparisons. Blind-benchmark isolation and hostile-code containment are unqualified; ordinary host execution is used for the trusted synthetic fixtures.

Failed transport/authentication, missing parent evidence, cached responses, interrupted calls and incomplete trajectories remain ungraded. Required final text is a separate delivery gate. Timeouts signal native cancellation, await the provider, and verify the owned session where supported. OpenCode native idle was observed after the real deadline; descendant shutdown for Codex/Claude aborts and their complete partial-error export remain unqualified. Retained sessions/files support replay and remain owned; no unrelated session is deleted.

Accounting records per-attempt receipts, aggregate known usage and unknown-cost counts. Native reported cost may be an API-equivalent estimate; subscription cash payments/allowance are separate. Claude's native CLI can make auxiliary model calls: modelUsage retains those alongside the observed assistant model. No routing ranking or default change follows from these commissioning controls.

## Current qualification

- The adopted suite passes 65 offline tests, including strict native prompt, provider/model, session/parent, final response identity and complete current-turn accounting, plus publication bound to its actual operation.
- Completed OpenCode Go MiniMax M3, Kimi K3 and GLM 5.3 Flash controls each passed all 52 independent checks on the first attempt. Each native history was independently bound and replayed; original raw receipts remain immutable.
- Puck stores these three actual native evals and their retained trial archives. Offline Puck execution and one-command publication also passed; service restart survival and isolated whole-store restore were verified.
- These results qualify one bounded synthetic multi-file task with scoped tools on Forge. They do not establish broad competency, a blind benchmark, a model ranking or Puck-native OpenCode authentication.

## Historical commissioning evidence

The following records describe the earlier staging source and controls, before
the completed OpenCode qualification and adopted adapter hardening:

- 38 offline behavioral tests pass, including lifecycle, tamper checks, donor provenance, current Codex transcript binding and loopback binding.
- Actual Promptfoo demo runs preserve first-pass failure and one-repair success; both snapshots independently replay. Native failed commissioning runs remain historical rather than being overwritten.
- Codex observed gpt-6.1-sol/medium completed the task and passes 52. CODEX-BINDING-CORRECTION.json verifies current response_item user binding against its retained JSONL; the original collector's obsolete event-message assumption remains recorded. No extra model call was used to correct that checker.
- Claude observed claude-opus-5-5 on CondorJF completes first-pass 52, with 20 native messages and successful root offline replay. Its login/versions are recorded in the retained peer receipt; the original runtime record exists but initially lacked version fields. Current adapter records version metadata for subsequent runs.
- OpenCode observed Go/minimax-m3 denied the outside canary, performed in-scope reads/writes/edits, then exceeded 180s before final delivery. Native idle after cancellation and partial history are preserved; task remains unaccepted/ungraded. The first commissioning run's absolute-policy mismatch is separately reclassified as a harness fault. No promotion follows from these attempts.
- Seven previously inspected Rust/C++ deliveries reproduce their historical PASS offline. Four empty deliveries and one ambiguous two-fence source remain ungraded in the portable replay, without changing prior receipts.

The complete historical evidence and current `OPENCODE-QUALIFICATION.md` remain
in Agency corpus entry `0418.f04e.converge.harness`. This source includes the
reduced, hash-provenanced native fixture needed for its offline regression
tests; `SOURCE-PROVENANCE.json` records the original portable import and
intentional source changes. The Puck service retains actual eval exports and
complete synthetic trial archives.

## Historical source replay

```sh
node src/historical-regrade.mjs SCREEN_DIR ORACLE_DIR SAVED_GRADES_JSON
```

It verifies donor hashes and the previously inspected source hash before compiling with rustc/clang++. It rejects ambiguous/uninspected source instead of executing it. Original screening receipts and manifests remain unchanged.

## Puck results authority

This source now lives in `e0da/actions/tools/agency-eval`. The source import is
recorded in `SOURCE-PROVENANCE.json`; runtime configuration, login data and
trial outputs stay ignored. `e0da/stack/promptfoo` owns the persistent service;
`e0da/ops/bin/promptfoo-service` owns private access and recovery.

Run and publish the offline commissioning task:

```sh
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm ci
npm run publish
```

Run a selected native route with its existing local login and publish both the
Promptfoo record and retained trial evidence on Puck:

```sh
npm run publish -- --native --config /absolute/runtime.local.json
```

The command uses `~/src/ops/bin/promptfoo-service` (override with `--operator`)
and SSH host `puck` (override with `--host`). It never uploads credentials or
config and never uses Promptfoo Cloud. An explicit native config is required
before paid or subscription execution. Trial deadlines remain bounded, with at
most one diagnosed repair. Publish an existing run without another model call:

```sh
npm run publish -- --run /absolute/runs/run-id --database /absolute/.promptfoo
```

Open the durable service through private SSH forwarding:

```sh
~/src/ops/bin/promptfoo-service access
# http://127.0.0.1:15600
```

The Puck service has no provider credentials. Evaluation jobs execute on the
native authenticated worker, then imports preserve the original eval ID and
hash-bind the immutable export. Duplicate identical imports are accepted;
changed payloads for that eval ID are rejected. Raw trial archives are retained
beside the database, and the whole store is covered by Ops backup/restore.

The browser service is https://promptfoo.e0da.io through existing e0da GitHub
Cloudflare Access. Raw native credentials remain on workers. Original OpenCode provider
cost/token fields in Promptfoo 0.123.1 describe its last assistant step and
can undercount the complete native turn. The adopted adapter now aggregates
all assistant steps for the exact current user parent, preserves unknown
fields and retains the original last-step report. This correction is tested
against retained native transcripts; original published qualification rows
remain unchanged and must be compared using their retained native totals.
Costs describe API-equivalent native estimates, not subscription cash charges. Upstream export timestamps vary per transfer, so idempotent ingestion
compares all exported fields except `metadata.exportedAt`.
