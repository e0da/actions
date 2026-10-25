# Infrastructure-control execution boundary

Platform composes authenticated control/API requests. Actions owns reusable
workflow execution. Stack owns desired catalog and release initiation; Ops
owns substrate and credentials. MCOG owns messaging/personas/jobs, and all chat
clients consume these contracts.

`tools/control/deployment_plan.rb` validates an offline digest-roll request for
existing `.github/workflows/deploy-k3s.yml`. It emits schema
`e0da.deployment-plan/v1`, normalized workflow inputs, risk and required live
evidence. It never calls GitHub, obtains credentials, runs a shell or deploys.
Its admission is intentionally stricter than a general image reference:
`ghcr.io/e0da/<service>@sha256:<64 lowercase hex>` and namespace `ops-services`.
This matches the current fleet/registry boundary. This is input preview, not
proof of a live deployment or a grant to execute it.

Run `ruby tests/control/test_deployment_plan.rb` and inspect workflow changes
before broadening this contract. No new workflow trigger is added. A future
Platform adapter must pin the approved workflow ref, resolve the exact service
and runner from Stack, validate required authority, correlate a durable request
ID to the real GitHub run, and retain run ID/URL, head SHA, digest and native
conclusion. A transport timeout with no authoritative run ID is uncertain;
never blindly dispatch another deployment. Workflow cancellation is not proof
that a rollout was undone. Existing image-existence, digest-roll, readiness and
rollback logic remains the sole executor.

See [Platform contract](https://github.com/e0da/platform/blob/gauge/infrastructure-control/docs/infrastructure-control.md) and
[Ops outage guide](https://github.com/e0da/ops/blob/gauge/infrastructure-control/docs/infrastructure-control-outage.md).
