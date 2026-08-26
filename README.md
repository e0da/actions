# e0da/actions

Shared CI/CD workflows and custom actions for e0da repos.

## Workflows

### `ci.yml` — Repository self-CI

Runs on pull requests and pushes to `main` in this repository. It validates the
shared workflow files with `actionlint` and runs the shell fixture suites that
exercise hosted-drift and runner-manifest behavior. The other `ci-*`,
`deploy-*`, and `release-*` workflow files remain reusable caller contracts; this
workflow is the source-repo gate for changes to those contracts.

### `actions-linux-arm64-smoke.yml` — Manual Actions ARC runner proof

Manual `workflow_dispatch` smoke test for the `actions-linux-arm64` ARC scale
set runner lane. It verifies host identity, Docker socket access, and Linux
ARM64 container execution.

### `ci-baseline.yml` — All repos

Checks that apply universally:

- **PR title**: must follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat|fix|chore|docs|refactor|test|ci: description`)
- **PR body**: must be exactly `Refs E0D-<number>` after trailing whitespace is removed; validation reads the current GitHub body so editing the body and rerunning the check recovers without another commit
- **Secret scan**: installs a pinned [Gitleaks](https://github.com/gitleaks/gitleaks) CLI release and scans full history

Branch names are intentionally not checked here. Graphite owns branch naming and
stack process for repos that use Graphite.

Callers can override `runner` when both baseline jobs should run on a different
runner label, for example `puck-linux-arm64`.

### `approval-gate.yml` — Advisory approval report

Advisory report that accepts either a real GitHub `APPROVED` review or a real
allowed `approved[...]` GitHub label as merge-approval evidence. It inspects
live GitHub review and label state; comments containing approval-looking text
do not count. The current contract is
documented in [`docs/samos-ci-m10-approval-gate-contract.md`](docs/samos-ci-m10-approval-gate-contract.md).

Missing approval evidence does not fail CI. CI remains a build/test health
surface; Agency and Graphite merge loops enforce approval before `gt merge`.
Do not add this job as a required status check.

Callers can override `runner` and configure exact `allowed-labels`.
The reusable job installs GitHub CLI on Linux self-hosted runners when `gh` is
not already on `PATH`, so callers do not need to treat `gh` as a preinstalled
runner capability.

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

### `ci-typescript-bun.yml` — TypeScript/Bun repos

Runs `bun install`, exports optional CI env entries, runs these package scripts
when present, and then runs `bun test`:

- `bun run format:check`
- `bun run lint`
- `bun run build`
- `bun run check`

The test step always runs; callers can replace it with `test-command`. Callers
can also override the format, lint, build, and check commands, request
`chromium`, `firefox`, or `webkit` with `playwright-browser`, and pass
newline-delimited non-secret CI environment entries through `env`.

The workflow reads package metadata through Bun. It does not scan repository
files, install ripgrep, or install OS packages. The requested Playwright browser
payload installs after the caller's frozen dependency install.

### `ci-node-npm.yml` — Node repos with a `package-lock.json`

For repos that install with npm, not bun. Use `ci-typescript-bun.yml` instead
when the repo has a `bun.lock`.

Three steps:

- `npm ci` — always. This is the only install command that consumes
  `package-lock.json`, and it fails when the lockfile and `package.json`
  disagree. That makes it the gate for a lockfile-only dependency bump.
- `npm run build` — only when `package.json` has a `build` script.
- `test-command` — only when the caller passes one.

The test step is opt-in on purpose. Several Node repos ship a placeholder test
script (`echo "Error: no test specified" && exit 1`). Auto-running `npm test`
because a `test` script exists would fail CI without proving anything, so the
caller has to name a real command.

Callers can override `runner`, `node-version`, and `test-command`.

```yaml
jobs:
  node:
    uses: e0da/actions/.github/workflows/ci-node-npm.yml@main
    with:
      node-version: "20"
      test-command: npm test -- --watchAll=false
```

### `ci-markdown.yml` — Markdown-heavy repos

- **Link check**: lychee scans all `.md` files for broken external links. Linux
  runners use `lycheeverse/lychee-action` by default. Callers with documented
  self-hosted runner capability can set `tool-mode: runner-preinstalled` to
  require `lychee` on PATH and run it directly. macOS self-hosted runners
  install or use the Homebrew `lychee` package in the default mode.
- **YAML frontmatter**: validates that any `---` frontmatter blocks are valid YAML

Callers can override `runner`, request `runner-capabilities`, choose
`tool-mode`, provide an optional `runner-manifest` contract JSON snippet, and
set the lychee argument string with `link-args`.

### `ci-bats.yml` — Shell/Bats repos

Installs `bats`, `rg`, and `shellcheck`, then runs the configured Bats command.

Callers can override `runner`, install extra apt packages with `system-deps`,
and override `test-command`.

### `ci-jekyll.yml` — Jekyll sites

Runs `ruby/setup-ruby` with Bundler caching on non-macOS runners, then builds
the site with `bundle exec jekyll build --strict_front_matter`. On macOS
self-hosted runners, the workflow uses Homebrew Ruby and an explicit
`bundle install` path instead of `ruby/setup-ruby`; the `ruby-version` input maps
to a Homebrew formula such as `ruby@3.2`. Build and test commands run in a
non-login shell so the runner PATH remains intact.

Callers can override `runner`, `ruby-version`, `build-command`, and provide an
optional `test-command` for site-specific structural checks. The workflow
installs `rg` so those checks can use the shared fast-search baseline.

### `ci-elixir.yml` — Elixir/Mix repos

Runs `erlef/setup-beam` by default, caches `deps` and `_build`, installs test
dependencies, then runs `mix ci` by default. Trusted self-hosted callers can
set `beam-mode: runner-preinstalled` when the runner image owns the requested
BEAM version. Callers can also set `cache-mode: off` for measured cache
experiments.

Callers can override `runner`, `otp-version`, `elixir-version`,
`deps-command`, `ci-command`, `cache-mode`, and `beam-mode`.

### `ci-opentofu.yml` — OpenTofu repos

Runs `opentofu/setup-opentofu`, then:

- formatting check, default `tofu fmt -check -recursive`
- validation, default `make validate`

Callers can override `fmt-command`, `validate-command`, `tofu-version`, and
`runner`. The workflow also enables OpenTofu provider resilience by default:
`provider-cache-mode: restore`, `provider-download-retry: 3`,
`registry-discovery-retry: 3`, `registry-client-timeout: 30`,
`validate-timeout-minutes: 10`, and `go-debug: http2client=0`. Set
`provider-cache-mode: read-write` only for deliberate cache-warming runs because
provider-cache uploads can dominate self-hosted runner tail latency. Set
`provider-cache-mode: off` for measured no-cache runs. Override `go-debug` only
when a caller needs OpenTofu's Go HTTP client to use the runtime default
transport behavior. Callers can also provide an optional `runner-manifest`
contract JSON snippet to validate requested capabilities before setup runs.

### `ci-rust.yml` — Rust repos

Runs `cargo fmt`, `cargo clippy`, `cargo nextest`, and `cargo build`.

Callers can override `runner`, the Rust toolchain, feature flags, test args,
and apt system dependencies. The workflow installs `rustup` when a self-hosted
runner does not already provide it, then installs the requested toolchain. For
integration tests that need NATS, callers can set `start-nats-jetstream: true` and
`nats-test-url: nats://localhost:4222`. Rust dependency and target caches stay
enabled, but `${CARGO_HOME}/bin` is not cached; executable Rust tools are owned
by the runner image or explicit install steps, not by restored cache state. The
Rust cache namespace is `v1-rust-nobin`, which intentionally avoids restoring
older `v0-rust` archives that were created before executable-bin caching was
disabled.

### `ci-unity.yml` — Unity Android projects

Runs Unity projects through the shared Android build gate on a macOS ARM64
runner. The workflow validates the runner profile, checks out Git LFS content,
requires the requested Unity editor version under `/Applications/Unity/Hub`,
requires Android Build Support with SDK, NDK, and OpenJDK, runs the
caller-owned repository check command, opens the project in batch mode, runs
Unity tests, invokes the caller-owned static build method, and uploads the build
artifact plus Unity logs. The reusable contract defaults to Unity `6000.3.22f1`
and requires a non-empty Unity Test Runner result XML whenever tests are
enabled. Test results and logs are retained by the always-running diagnostic
artifact upload, including when a test or build step fails.

Callers must provide `project-path` and `build-method`. Common overrides are
`runner`, `runner-profile`, `unity-version`, `check-command`, `run-tests`,
`test-platform`, `build-target`, `build-output-dir`, and `artifact-name`.

### `release-rust.yml` — Rust release artifacts

Reusable release workflow for tagged Rust binary releases. It validates the
release tag against a Cargo package version, builds requested target archives,
publishes a GitHub Release, and can optionally push a GHCR image. Set
`cargo-package` for virtual workspaces or when the released binary belongs to a
specific workspace package.

Default targets stay compatible with existing callers:

- `aarch64-apple-darwin`
- `x86_64-unknown-linux-musl`

Callers can include `aarch64-unknown-linux-musl` in `targets` to build a native
Linux ARM64 musl artifact on the `linux-arm64-runner`, which defaults to
`puck-linux-arm64`. The workflow supports Debian/Ubuntu (`apt-get`) and Alpine
(`apk`) musl setup on Linux runners. The build matrix is generated from
`targets`, so unrequested platforms do not allocate a runner just to skip.
Rust release caches also skip `${CARGO_HOME}/bin` so release dependency reuse
does not persist executable tool state across runner images or products. Release
Rust caches use the same `v1-rust-nobin` namespace as CI Rust caches.

Runner override inputs:

- `validate-runner`
- `linux-x64-runner`
- `linux-arm64-runner`
- `publish-runner`
- `image-runner`

### `release-elixir.yml` — Elixir/Phoenix release images

Reusable release workflow for tagged Elixir/Phoenix services. It validates the
release tag against the Mix project version, prepares GHCR image tags, can push
a multi-architecture Docker image, and can optionally create a GitHub Release.
When `push-latest` is enabled, `:latest` is added only for non-prerelease
versions; prereleases keep immutable version tags unless callers provide
explicit `extra-tags`.

Required inputs:

- `app-name`
- `image-name`

Common overrides:

- `validate-runner`
- `image-runner`
- `publish-runner`
- `otp-version`
- `elixir-version`
- `beam-mode`
- `deps-command`
- `version-command`
- `tag-prefix`
- `docker-context`
- `dockerfile`
- `platforms`
- `build-args`
- `target`
- `push-image`
- `push-latest`
- `extra-tags`
- `publish-github-release`

The default `version-command` reads `mix.exs` metadata without loading
`config/runtime.exs`, so Phoenix apps do not need deployment-only environment
variables such as `DATABASE_URL` merely to validate a release tag.

Trusted self-hosted callers can set `beam-mode: runner-preinstalled` when the
runner image owns the requested BEAM version. Service repos should keep only a
thin release caller and app-owned Dockerfile/release scripts; shared release
policy belongs here.

### `release-homebrew-interface.yml` — Homebrew release-interface proof

Reusable release workflow for active non-service products that expose an
app-owned `scripts/release-interface` contract. It runs the interface's
`metadata`, `test`, `build`, and `smoke` verbs, packages the build output with a
checksum, can publish those assets to the current GitHub tag release, and can
prove the installed Homebrew formula with `brew fetch`, `brew install`, and
`brew test`.

This workflow is for installable product surfaces such as ALX and Mozak. The
app repo owns how to build and smoke its payload; `e0da/actions` owns the shared
orchestration and evidence shape.

Required input:

- `homebrew-formula`

Common overrides:

- `release-interface`
- `build-output-dir`
- `built-binary-name`
- `artifact-name`
- `setup-bun`
- `bun-version`
- `bun-install-command`
- `release-env`
- `homebrew-build-packages`
- `publish-runner`
- `homebrew-tap`
- `publish-github-release`
- `run-homebrew-proof`
- `installed-smoke-command`

For TypeScript/Bun products, set `setup-bun: true`; use `bun-version` when the
repo needs a pinned Bun version. `release-env` exports newline-delimited
`KEY=VALUE` entries before every release-interface verb, and
`homebrew-build-packages` installs newline-delimited build-time Homebrew tools
such as `sops` on macOS release runners.

For the private `e0da/internal` tap, callers that leave
`run-homebrew-proof: true` must provide `HOMEBREW_GITHUB_API_TOKEN` so Homebrew
can read the private tap and private release assets. `publish-github-release`
only runs on tag refs; non-tag callers fail before release publication.

## How to adopt

In any repo, create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  baseline:
    uses: e0da/actions/.github/workflows/ci-baseline.yml@main

  # Add for TypeScript/Bun repos:
  typescript:
    uses: e0da/actions/.github/workflows/ci-typescript-bun.yml@main

  # Add for Node repos with a package-lock.json:
  node:
    uses: e0da/actions/.github/workflows/ci-node-npm.yml@main

  # Add for markdown-heavy repos:
  markdown:
    uses: e0da/actions/.github/workflows/ci-markdown.yml@main

  # Add for shell/Bats repos:
  bats:
    uses: e0da/actions/.github/workflows/ci-bats.yml@main

  # Add for Jekyll sites:
  jekyll:
    uses: e0da/actions/.github/workflows/ci-jekyll.yml@main

  # Add for Elixir/Mix repos:
  elixir:
    uses: e0da/actions/.github/workflows/ci-elixir.yml@main

  # Add for OpenTofu repos:
  opentofu:
    uses: e0da/actions/.github/workflows/ci-opentofu.yml@main

  # Add for Rust repos:
  rust:
    uses: e0da/actions/.github/workflows/ci-rust.yml@main

  # Add for Unity Android repos:
  unity:
    uses: e0da/actions/.github/workflows/ci-unity.yml@main
    with:
      project-path: unity/GalliumXR
      build-method: Gallium.Build.CI.BuildAndroid
```

Mix and match — only include the workflows relevant to each repo.

For Elixir/Phoenix service image releases, create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags: ["v*"]

permissions:
  contents: write
  packages: write

jobs:
  release:
    uses: e0da/actions/.github/workflows/release-elixir.yml@main
    with:
      app-name: platform
      image-name: ghcr.io/e0da/platform
      push-image: true
      publish-github-release: true
    secrets: inherit
```

### Adoption: yoda

```yaml
jobs:
  baseline:
    uses: e0da/actions/.github/workflows/ci-baseline.yml@main
  typescript:
    uses: e0da/actions/.github/workflows/ci-typescript-bun.yml@main
```

### Adoption: dots

```yaml
jobs:
  baseline:
    uses: e0da/actions/.github/workflows/ci-baseline.yml@main
  markdown:
    uses: e0da/actions/.github/workflows/ci-markdown.yml@main
```

## Adding a new workflow type

1. Create `.github/workflows/ci-<type>.yml` or `.github/workflows/release-<type>.yml` in this repo using `workflow_call:` as the trigger
2. Update this README with what it checks and when to adopt it
3. Commit to `main` — adopters pin to `@main` so they pick it up automatically

## Custom actions roadmap

Future `actions/` directory will house composite actions for:

- Release tagging (`git describe` → GitHub Release)
- Graphite stack validation
- Bun lockfile freshness check
