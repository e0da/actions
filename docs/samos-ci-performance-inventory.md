# SAMOS CI Performance Inventory

Date: 2026-05-28

Scope: E0D-1002 under E0D-999. This inventories reusable workflows in
`e0da/actions` as they are used by the active SAMOS repos: `actions`, `ops`,
`stack`, `mcog`, `symphonic`, and `wiki`. It records current setup overhead and
candidate policy knobs only; it does not implement new inputs.

Related follow-up: Node 24 runtime compatibility for marketplace actions is
tracked in
[E0D-1005](https://linear.app/e0da/issue/E0D-1005/actions-upgrade-marketplace-actions-for-node-24-runtime-compatibility).
Per E0D-1005, GitHub's official changelog says the Node 24 default begins on
2026-06-16. That follow-up now upgrades or replaces Node-backed marketplace
actions while preserving hosted runner defaults.

## Method

Evidence is limited to local repo files read during this inventory. Citations use
paths relative to `/Users/bug/src/actions` when the file is in this repo and
`../<repo>/...` when the evidence is in another active SAMOS repo.

## E0D-1005 Node 24 Marketplace Action Decision

Pre-change inventory from the reusable workflows:

| Action | Before E0D-1005 | Decision |
| --- | --- | --- |
| `actions/checkout` | `v4`, Node 20 | Upgrade to `v5`, which uses Node 24. Do not use `v6` yet because this repo has not tested the `v6` credential persistence behavior. |
| `actions/cache` | `v4`, Node 20 | Upgrade to `v5`, which uses Node 24. |
| `actions/upload-artifact` | `v4`, Node 20 | Upgrade to `v7`, which uses Node 24. |
| `actions/download-artifact` | `v4`, Node 20 | Upgrade to `v8`, which uses Node 24. |
| `opentofu/setup-opentofu` | `v1`, Node 20 | Upgrade to `v2`, which uses Node 24 and preserves the current `tofu_version` and `tofu_wrapper` inputs. |
| `softprops/action-gh-release` | `v2`, Node 20 | Upgrade to `v3`, which uses Node 24 and preserves the current release inputs. |
| `docker/login-action` | `v3`, Node 20 | Upgrade to `v4`, which uses Node 24 and preserves the current registry login inputs. |
| `docker/setup-buildx-action` | `v3`, Node 20 | Upgrade to `v4`, which uses Node 24. |
| `docker/build-push-action` | `v6`, Node 20 | Upgrade to `v7`, which uses Node 24 and preserves the current build inputs. |
| `gitleaks/gitleaks-action` | `v2`, Node 20; no Node 24 major currently available | Replace with direct `gitleaks` CLI execution pinned to `v8.30.1`, downloaded from the official `gitleaks/gitleaks` release assets with per-runner sha256 verification. This avoids deferring E0D-1005 on the baseline secret-scan path. |
| `ruby/setup-ruby` | `v1`, Node 24 | Keep. |
| `erlef/setup-beam` | `v1`, Node 24 | Keep. |
| `oven-sh/setup-bun` | `v2`, Node 24 | Keep. |
| `Swatinem/rust-cache` | `v2`, Node 24 | Keep. |
| `lycheeverse/lychee-action` | `v2`, composite action | Keep. |
| `taiki-e/install-action` | `v2`, composite action | Keep. |

Hosted fallback compatibility remains unchanged: reusable workflow runner inputs
still default to `ubuntu-latest` where they did before, and Puck-specific deploy
or smoke workflows keep their existing self-hosted runner labels.

## Active SAMOS Call Sites

| Repo | Workflow call | Current runner inputs | Other notable inputs | Evidence |
| --- | --- | --- | --- | --- |
| `ops` | `ci-baseline.yml`, `ci-opentofu.yml` | Both pass `runner: puck-linux-arm64`. | No cache or artifact inputs. | `../ops/.github/workflows/ci.yml:18`, `../ops/.github/workflows/ci.yml:21`, `../ops/.github/workflows/ci.yml:24`, `../ops/.github/workflows/ci.yml:28` |
| `stack` | `ci-baseline.yml`, `ci-markdown.yml` | Both pass `runner: puck-linux-arm64`. | `stack` also has local self-hosted Bun and shellcheck jobs outside the reusable workflows. | `../stack/.github/workflows/ci.yml:18`, `../stack/.github/workflows/ci.yml:22`, `../stack/.github/workflows/ci.yml:25`, `../stack/.github/workflows/ci.yml:29`, `../stack/.github/workflows/ci.yml:31`, `../stack/.github/workflows/ci.yml:45` |
| `stack` | `deploy-compose.yml` | Reusable deploy hard-codes `[self-hosted, puck]`; callers do not pass a runner. | Uses archetypes B, C, and D across `chat`, `gateway`, `mcog`, `mm`, `nats`, `symphonic`, and `wiki`; some callers set encrypted env files, `skip-pull`, or healthchecks. | `.github/workflows/deploy-compose.yml:70`, `.github/workflows/deploy-compose.yml:73`, `../stack/.github/workflows/deploy-chat.yml:22`, `../stack/.github/workflows/deploy-gateway.yml:22`, `../stack/.github/workflows/deploy-mcog.yml:27`, `../stack/.github/workflows/deploy-mm.yml:22`, `../stack/.github/workflows/deploy-nats.yml:19`, `../stack/.github/workflows/deploy-symphonic.yml:23`, `../stack/.github/workflows/deploy-wiki.yml:24` |
| `mcog` | `ci-baseline.yml` | Passes `runner: puck-linux-arm64`. | The Mix job remains local and self-hosted, with its own cache. | `../mcog/.github/workflows/ci.yml:18`, `../mcog/.github/workflows/ci.yml:21`, `../mcog/.github/workflows/ci.yml:24`, `../mcog/.github/workflows/ci.yml:45` |
| `mcog` | `deploy-compose.yml` | Reusable deploy hard-codes `[self-hosted, puck]`. | Caller uses archetype B, encrypted YAML env, and a readiness healthcheck. | `../mcog/.github/workflows/deploy.yml:73`, `../mcog/.github/workflows/deploy.yml:76`, `../mcog/.github/workflows/deploy.yml:78`, `../mcog/.github/workflows/deploy.yml:80` |
| `symphonic` | `ci-baseline.yml` | Passes `runner: puck-linux-arm64`. | The Mix jobs remain local and self-hosted. | `../symphonic/.github/workflows/ci.yml:18`, `../symphonic/.github/workflows/ci.yml:21`, `../symphonic/.github/workflows/ci.yml:24`, `../symphonic/.github/workflows/ci.yml:26` |
| `symphonic` | `deploy-compose.yml` | Reusable deploy hard-codes `[self-hosted, puck]`. | Caller uses archetype B plus an RPC healthcheck. | `../symphonic/.github/workflows/release.yml:118`, `../symphonic/.github/workflows/release.yml:121`, `../symphonic/.github/workflows/release.yml:123` |
| `wiki` | `ci-baseline.yml`, `ci-markdown.yml`, `ci-jekyll.yml` | All pass `runner: puck-macos-arm64`. | Markdown overrides `link-args`; Jekyll adds a repo test command. | `../wiki/.github/workflows/ci.yml:15`, `../wiki/.github/workflows/ci.yml:18`, `../wiki/.github/workflows/ci.yml:21`, `../wiki/.github/workflows/ci.yml:24`, `../wiki/.github/workflows/ci.yml:27`, `../wiki/.github/workflows/ci.yml:28`, `../wiki/.github/workflows/ci.yml:36`, `../wiki/.github/workflows/ci.yml:39`, `../wiki/.github/workflows/ci.yml:40` |
| `wiki` | `deploy-compose.yml` | Reusable deploy hard-codes `[self-hosted, puck]`. | Caller uses archetype A with uploaded `wiki-site` artifact and bind target `/Users/e0da/.wiki-site`. | `../wiki/.github/workflows/deploy.yml:44`, `../wiki/.github/workflows/deploy.yml:47`, `../wiki/.github/workflows/deploy.yml:49`, `../wiki/.github/workflows/deploy.yml:51` |

No active SAMOS repo currently calls `ci-bats.yml`, `ci-typescript-bun.yml`,
`ci-elixir.yml`, `ci-rust.yml`, or `release-rust.yml` from `e0da/actions` in the
searched `.github/workflows` files. They remain relevant shared-workflow
surfaces because they already expose setup/cache/release behavior and may be
adopted by active repos later.

## Reusable Workflow Setup Inventory

### `ci-baseline.yml`

- Runner input: `runner`, default `ubuntu-latest`; both jobs use
  `${{ inputs.runner }}`. Preserve this hosted default for existing callers.
  Evidence: `.github/workflows/ci-baseline.yml:6`,
  `.github/workflows/ci-baseline.yml:10`,
  `.github/workflows/ci-baseline.yml:15`,
  `.github/workflows/ci-baseline.yml:56`.
- Setup overhead: PR title job shells out to `gh api`; secret scan checks out
  full history, downloads a pinned Gitleaks CLI release, verifies its sha256,
  and runs `gitleaks detect`. Evidence:
  `.github/workflows/ci-baseline.yml:21`,
  `.github/workflows/ci-baseline.yml:31`,
  `.github/workflows/ci-baseline.yml:62`,
  `.github/workflows/ci-baseline.yml:66`,
  `.github/workflows/ci-baseline.yml:100`,
  `.github/workflows/ci-baseline.yml:108`.
- Cache behavior: none.
- Artifact behavior: none.
- Architecture assumptions: assumes `gh` is available on the runner for PR title
  resolution. That is usually true on hosted runners, but is a runner-capability
  requirement for self-hosted lanes. Evidence:
  `.github/workflows/ci-baseline.yml:31`.

### `ci-markdown.yml`

- Runner input: `runner`, default `ubuntu-latest`; both jobs use it. Preserve
  hosted default compatibility. Evidence: `.github/workflows/ci-markdown.yml:6`,
  `.github/workflows/ci-markdown.yml:10`,
  `.github/workflows/ci-markdown.yml:26`,
  `.github/workflows/ci-markdown.yml:68`.
- Setup overhead: Linux link checking delegates to `lycheeverse/lychee-action`;
  macOS installs `lychee` with Homebrew if missing. YAML frontmatter validation
  uses Ruby from the runner. Evidence: `.github/workflows/ci-markdown.yml:30`,
  `.github/workflows/ci-markdown.yml:32`,
  `.github/workflows/ci-markdown.yml:39`,
  `.github/workflows/ci-markdown.yml:51`,
  `.github/workflows/ci-markdown.yml:74`.
- Cache behavior: none.
- Artifact behavior: none.
- Architecture assumptions: supports Linux and macOS only. Evidence:
  `.github/workflows/ci-markdown.yml:60`,
  `.github/workflows/ci-markdown.yml:61`,
  `.github/workflows/ci-markdown.yml:63`.

### `ci-jekyll.yml`

- Runner input: `runner`, default `ubuntu-latest`; job uses it. Preserve hosted
  default compatibility. Evidence: `.github/workflows/ci-jekyll.yml:6`,
  `.github/workflows/ci-jekyll.yml:10`,
  `.github/workflows/ci-jekyll.yml:30`.
- Setup overhead: non-macOS uses `ruby/setup-ruby@v1` with Bundler cache; macOS
  maps `ruby-version` to a Homebrew formula, installs Ruby if missing, installs
  Bundler, and runs `bundle install`. Evidence:
  `.github/workflows/ci-jekyll.yml:38`,
  `.github/workflows/ci-jekyll.yml:40`,
  `.github/workflows/ci-jekyll.yml:43`,
  `.github/workflows/ci-jekyll.yml:45`,
  `.github/workflows/ci-jekyll.yml:55`,
  `.github/workflows/ci-jekyll.yml:63`,
  `.github/workflows/ci-jekyll.yml:72`,
  `.github/workflows/ci-jekyll.yml:74`.
- Cache behavior: hosted/non-macOS Bundler cache is on through
  `ruby/setup-ruby`; macOS uses `$RUNNER_TEMP/bundle` and does not use a
  persisted Actions cache. Evidence: `.github/workflows/ci-jekyll.yml:43`,
  `.github/workflows/ci-jekyll.yml:73`.
- Artifact behavior: none.
- Architecture assumptions: non-macOS setup depends on `ruby/setup-ruby`; macOS
  assumes Homebrew exists. `ripgrep` setup supports Darwin, Linux apt, and Linux
  apk. Evidence: `.github/workflows/ci-jekyll.yml:50`,
  `.github/workflows/ci-jekyll.yml:84`,
  `.github/workflows/ci-jekyll.yml:85`,
  `.github/workflows/ci-jekyll.yml:92`,
  `.github/workflows/ci-jekyll.yml:93`,
  `.github/workflows/ci-jekyll.yml:96`.

### `ci-opentofu.yml`

- Runner input: `runner`, default `ubuntu-latest`; job uses it. Preserve hosted
  default compatibility. Evidence: `.github/workflows/ci-opentofu.yml:6`,
  `.github/workflows/ci-opentofu.yml:10`,
  `.github/workflows/ci-opentofu.yml:30`.
- Setup overhead: always checks out and runs `opentofu/setup-opentofu@v2` with
  wrapper disabled, then runs configurable format and validate commands.
  Evidence: `.github/workflows/ci-opentofu.yml:34`,
  `.github/workflows/ci-opentofu.yml:36`,
  `.github/workflows/ci-opentofu.yml:37`,
  `.github/workflows/ci-opentofu.yml:40`,
  `.github/workflows/ci-opentofu.yml:42`,
  `.github/workflows/ci-opentofu.yml:47`.
- Cache behavior: none.
- Artifact behavior: none.
- Architecture assumptions: relies on the setup action instead of a runner-local
  `tofu` binary.

### `deploy-compose.yml`

- Runner input: none. The deploy job currently hard-codes `[self-hosted, puck]`.
  This is an explicit Puck-only reusable today. Evidence:
  `.github/workflows/deploy-compose.yml:70`,
  `.github/workflows/deploy-compose.yml:73`.
- Setup overhead: archetypes B/C/D refresh the long-lived stack working tree with
  `git fetch` and `git reset --hard origin/main`; archetype A downloads an
  artifact; encrypted env files are decrypted with a Puck-local age key; B/C/D
  create an ephemeral Docker config; B/D may pull images; C builds locally.
  Evidence: `.github/workflows/deploy-compose.yml:98`,
  `.github/workflows/deploy-compose.yml:121`,
  `.github/workflows/deploy-compose.yml:122`,
  `.github/workflows/deploy-compose.yml:125`,
  `.github/workflows/deploy-compose.yml:132`,
  `.github/workflows/deploy-compose.yml:136`,
  `.github/workflows/deploy-compose.yml:179`,
  `.github/workflows/deploy-compose.yml:213`,
  `.github/workflows/deploy-compose.yml:230`,
  `.github/workflows/deploy-compose.yml:243`.
- Cache behavior: none.
- Artifact behavior: archetype A downloads an artifact into `_artifact`; no
  uploads happen here. Evidence: `.github/workflows/deploy-compose.yml:125`,
  `.github/workflows/deploy-compose.yml:127`,
  `.github/workflows/deploy-compose.yml:130`.
- Clean behavior: deletes the ephemeral Docker config and decrypted `.env` on
  `always()`. Archetype A uses `rsync --delete`, which is a destructive sync of
  the bind target by design. Evidence: `.github/workflows/deploy-compose.yml:176`,
  `.github/workflows/deploy-compose.yml:260`,
  `.github/workflows/deploy-compose.yml:264`,
  `.github/workflows/deploy-compose.yml:276`,
  `.github/workflows/deploy-compose.yml:280`.
- Architecture assumptions: assumes Puck paths, Puck age key location, Docker
  Desktop socket path, and `$HOME/.docker/cli-plugins`. Evidence:
  `.github/workflows/deploy-compose.yml:31`,
  `.github/workflows/deploy-compose.yml:136`,
  `.github/workflows/deploy-compose.yml:204`,
  `.github/workflows/deploy-compose.yml:219`.

## Other Reusable Workflows Not Currently Called By Active SAMOS Repos

| Workflow | Runner inputs and hosted fallback | Setup/cache/artifact behavior | Architecture assumptions |
| --- | --- | --- | --- |
| `ci-bats.yml` | `runner`, default `ubuntu-latest`; job uses it. Evidence: `.github/workflows/ci-bats.yml:6`, `.github/workflows/ci-bats.yml:10`, `.github/workflows/ci-bats.yml:25`. | Installs `bats`, `ripgrep`, `shellcheck`, plus optional apt packages; no cache or artifacts. Evidence: `.github/workflows/ci-bats.yml:31`, `.github/workflows/ci-bats.yml:34`. | Assumes apt-based Linux. Evidence: `.github/workflows/ci-bats.yml:33`. |
| `ci-typescript-bun.yml` | `runner`, default `ubuntu-latest`; job uses it. Evidence: `.github/workflows/ci-typescript-bun.yml:6`, `.github/workflows/ci-typescript-bun.yml:10`, `.github/workflows/ci-typescript-bun.yml:50`. | Runs `oven-sh/setup-bun`, `bun install --frozen-lockfile`, optional apt `ripgrep`, optional Playwright install; no cache or artifacts. Evidence: `.github/workflows/ci-typescript-bun.yml:54`, `.github/workflows/ci-typescript-bun.yml:58`, `.github/workflows/ci-typescript-bun.yml:61`, `.github/workflows/ci-typescript-bun.yml:119`. | Ripgrep setup assumes apt if `rg` is missing. Evidence: `.github/workflows/ci-typescript-bun.yml:64`. |
| `ci-elixir.yml` | `runner`, default `ubuntu-latest`; job uses it. Evidence: `.github/workflows/ci-elixir.yml:6`, `.github/workflows/ci-elixir.yml:10`, `.github/workflows/ci-elixir.yml:35`. | Runs `erlef/setup-beam`, caches `deps` and `_build`, then runs configurable deps and CI commands. Evidence: `.github/workflows/ci-elixir.yml:43`, `.github/workflows/ci-elixir.yml:49`, `.github/workflows/ci-elixir.yml:52`, `.github/workflows/ci-elixir.yml:60`, `.github/workflows/ci-elixir.yml:63`. | Cache key varies by `runner.os`, OTP, Elixir, and `mix.lock`. Evidence: `.github/workflows/ci-elixir.yml:55`. |
| `ci-rust.yml` | `runner`, default `ubuntu-latest`; job uses it. Evidence: `.github/workflows/ci-rust.yml:43`, `.github/workflows/ci-rust.yml:46`, `.github/workflows/ci-rust.yml:83`. | Optional apt system deps, optional pinned SOPS, optional pinned NATS server, optional Docker NATS, Rust toolchain install, Rust cache, nextest install; no artifacts. Evidence: `.github/workflows/ci-rust.yml:98`, `.github/workflows/ci-rust.yml:104`, `.github/workflows/ci-rust.yml:135`, `.github/workflows/ci-rust.yml:168`, `.github/workflows/ci-rust.yml:183`, `.github/workflows/ci-rust.yml:190`, `.github/workflows/ci-rust.yml:195`. | SOPS and NATS installers support only `X64` and `ARM64` Linux runner architectures; Docker is required when `start-nats-jetstream` is true. Evidence: `.github/workflows/ci-rust.yml:115`, `.github/workflows/ci-rust.yml:120`, `.github/workflows/ci-rust.yml:124`, `.github/workflows/ci-rust.yml:146`, `.github/workflows/ci-rust.yml:151`, `.github/workflows/ci-rust.yml:155`, `.github/workflows/ci-rust.yml:172`. |
| `release-rust.yml` | Separate runner inputs: `validate-runner`, `linux-x64-runner`, `linux-arm64-runner`, `publish-runner`, `image-runner`. Hosted defaults remain `ubuntu-latest` except `linux-arm64-runner`, which defaults to `puck-linux-arm64`. Evidence: `.github/workflows/release-rust.yml:13`, `.github/workflows/release-rust.yml:16`, `.github/workflows/release-rust.yml:17`, `.github/workflows/release-rust.yml:20`, `.github/workflows/release-rust.yml:21`, `.github/workflows/release-rust.yml:24`, `.github/workflows/release-rust.yml:25`, `.github/workflows/release-rust.yml:28`, `.github/workflows/release-rust.yml:29`, `.github/workflows/release-rust.yml:32`. | Validates tag, installs Rust and musl tools, restores Rust cache, uploads binary artifacts, downloads all artifacts for release, optionally builds and pushes a container image. Evidence: `.github/workflows/release-rust.yml:61`, `.github/workflows/release-rust.yml:136`, `.github/workflows/release-rust.yml:144`, `.github/workflows/release-rust.yml:164`, `.github/workflows/release-rust.yml:194`, `.github/workflows/release-rust.yml:212`, `.github/workflows/release-rust.yml:247`, `.github/workflows/release-rust.yml:250`. | Matrix includes macOS ARM64 self-hosted, Linux ARM64 musl, and Linux x64 musl. Unrequested targets are skipped before toolchain/cache/build work. Evidence: `.github/workflows/release-rust.yml:107`, `.github/workflows/release-rust.yml:108`, `.github/workflows/release-rust.yml:109`, `.github/workflows/release-rust.yml:110`, `.github/workflows/release-rust.yml:111`, `.github/workflows/release-rust.yml:126`, `.github/workflows/release-rust.yml:136`, `.github/workflows/release-rust.yml:164`, `.github/workflows/release-rust.yml:170`. |

## Candidate Knobs

### `runner-profile`

Hypothesis: a logical runner profile should map to runner labels and capability
expectations without removing the existing raw `runner` inputs.

Evidence:

- Most reusable CI workflows expose a raw `runner` input with hosted
  `ubuntu-latest` default. Evidence: `.github/workflows/ci-baseline.yml:6`,
  `.github/workflows/ci-markdown.yml:6`, `.github/workflows/ci-jekyll.yml:6`,
  `.github/workflows/ci-opentofu.yml:6`.
- Active CI callers override raw runners to `puck-linux-arm64` or
  `puck-macos-arm64`. Evidence: `../ops/.github/workflows/ci.yml:21`,
  `../stack/.github/workflows/ci.yml:22`,
  `../wiki/.github/workflows/ci.yml:21`.
- `deploy-compose.yml` has no raw runner input and is Puck-specific today.
  Evidence: `.github/workflows/deploy-compose.yml:73`.

Compatibility policy: preserve raw `runner` inputs and hosted defaults. A
profile can be additive, not a replacement, so existing callers keep working.

### `tool-mode`

Hypothesis: workflows need an explicit tool setup policy such as `hosted-setup`,
`prefer-preinstalled`, or `force-install`.

Evidence:

- Markdown uses a hosted action on Linux and Homebrew on macOS. Evidence:
  `.github/workflows/ci-markdown.yml:31`, `.github/workflows/ci-markdown.yml:39`.
- Jekyll uses `ruby/setup-ruby` off macOS and Homebrew Ruby on macOS. Evidence:
  `.github/workflows/ci-jekyll.yml:38`, `.github/workflows/ci-jekyll.yml:45`.
- OpenTofu always uses `opentofu/setup-opentofu@v2`. Evidence:
  `.github/workflows/ci-opentofu.yml:36`.
- Rust always installs a toolchain and nextest, with optional installers for SOPS
  and NATS. Evidence: `.github/workflows/ci-rust.yml:183`,
  `.github/workflows/ci-rust.yml:195`,
  `.github/workflows/ci-rust.yml:104`,
  `.github/workflows/ci-rust.yml:135`.

Compatibility policy: default `tool-mode` should preserve the current hosted
setup behavior. Self-hosted lanes can opt into preinstalled tools only where the
runner capability is documented.

### `cache-mode`

Hypothesis: cache behavior should be explicit because hosted cache restoration
can be useful on GitHub-hosted runners but may be redundant or slower on stable
self-hosted runners.

Evidence:

- Jekyll non-macOS uses Bundler caching via `ruby/setup-ruby`; macOS uses
  `$RUNNER_TEMP/bundle`. Evidence: `.github/workflows/ci-jekyll.yml:43`,
  `.github/workflows/ci-jekyll.yml:73`.
- Elixir caches `deps` and `_build` using `actions/cache@v5`. Evidence:
  `.github/workflows/ci-elixir.yml:49`,
  `.github/workflows/ci-elixir.yml:52`.
- Rust and Rust release use `Swatinem/rust-cache@v2`. Evidence:
  `.github/workflows/ci-rust.yml:190`,
  `.github/workflows/release-rust.yml:164`.
- Active SAMOS reusable CI calls mostly use workflows with no explicit cache
  except `wiki` Jekyll. Evidence: `../wiki/.github/workflows/ci.yml:36`,
  `.github/workflows/ci-jekyll.yml:43`.

Compatibility policy: default cache mode should preserve current cache usage on
hosted defaults. Self-hosted cache bypass should be opt-in and measured.

### `artifact-mode`

Hypothesis: artifact policy matters primarily for release and static-bind deploy
paths, not baseline CI.

Evidence:

- `deploy-compose.yml` downloads artifacts only for archetype A. Evidence:
  `.github/workflows/deploy-compose.yml:125`,
  `.github/workflows/deploy-compose.yml:126`.
- `wiki` deploy uses archetype A with `wiki-site`. Evidence:
  `../wiki/.github/workflows/deploy.yml:47`,
  `../wiki/.github/workflows/deploy.yml:49`.
- `release-rust.yml` uploads per-target binary artifacts and downloads them for
  release publication. Evidence: `.github/workflows/release-rust.yml:194`,
  `.github/workflows/release-rust.yml:212`.

Compatibility policy: preserve artifact upload/download defaults for release and
archetype A. Additive artifact modes should only skip work when the caller has a
non-artifact path.

### `clean-mode`

Hypothesis: cleanup is already embedded in deploy and some local jobs; a future
knob should distinguish safety cleanup from expensive destructive cleanup.

Evidence:

- `deploy-compose.yml` resets the long-lived stack checkout for non-A deploys.
  Evidence: `.github/workflows/deploy-compose.yml:98`,
  `.github/workflows/deploy-compose.yml:122`.
- `deploy-compose.yml` removes ephemeral Docker config and decrypted `.env` with
  `always()`. Evidence: `.github/workflows/deploy-compose.yml:260`,
  `.github/workflows/deploy-compose.yml:276`.
- Archetype A uses `rsync --delete`. Evidence:
  `.github/workflows/deploy-compose.yml:176`.
- Rust CI removes a possibly-existing `ci-nats` container before starting a new
  one. Evidence: `.github/workflows/ci-rust.yml:172`.

Compatibility policy: do not disable secret or credential cleanup by default.
Any `clean-mode` should preserve current safe cleanup unless a caller explicitly
selects a narrower mode.

### `runner-capabilities`

Hypothesis: profile names alone are insufficient; setup decisions need declared
capabilities such as `gh`, Homebrew, Docker socket, Docker Compose plugin,
Ruby, `rg`, `tofu`, and architecture.

Evidence:

- Baseline calls `gh api`. Evidence: `.github/workflows/ci-baseline.yml:31`.
- macOS Markdown and Jekyll require Homebrew when tools are missing. Evidence:
  `.github/workflows/ci-markdown.yml:46`,
  `.github/workflows/ci-jekyll.yml:50`,
  `.github/workflows/ci-jekyll.yml:86`.
- Deploy assumes Docker Desktop socket and Docker Compose plugin location.
  Evidence: `.github/workflows/deploy-compose.yml:204`,
  `.github/workflows/deploy-compose.yml:219`.
- Rust installers branch on `runner.arch` for `X64` and `ARM64`. Evidence:
  `.github/workflows/ci-rust.yml:115`,
  `.github/workflows/ci-rust.yml:120`,
  `.github/workflows/ci-rust.yml:146`,
  `.github/workflows/ci-rust.yml:151`.

Compatibility policy: capabilities should be validation or setup selection
inputs, not hidden assumptions that change hosted behavior.

## SCIMAT

Gap statement: E0D-1002 asks for shared knobs after baseline, but the current
repos mix hosted defaults, raw runner labels, hard-coded Puck deploy assumptions,
and workflow-specific setup logic. The inventory must identify likely knobs
without prematurely changing workflow behavior.

| # | Hypothesis | Evidence | Citation | Conclusion | Confidence |
| --- | --- | --- | --- | --- | --- |
| 1 | `runner-profile` should be additive over raw runner inputs. | CI workflows already expose raw `runner` defaults, while active repos override to Puck labels. | `.github/workflows/ci-baseline.yml:10`; `../ops/.github/workflows/ci.yml:21`; `../wiki/.github/workflows/ci.yml:21` | Supports. Raw runner labels are the current compatibility contract. | HIGH, 90% |
| 2 | `tool-mode` is a first-order M1 knob because setup work dominates Markdown, Jekyll, OpenTofu, Rust, and TypeScript paths. | Workflows repeatedly install tools through setup actions, apt, Homebrew, or Rust-specific installers. | `.github/workflows/ci-markdown.yml:32`; `.github/workflows/ci-jekyll.yml:63`; `.github/workflows/ci-opentofu.yml:37`; `.github/workflows/ci-rust.yml:183` | Supports. This is broad and visible in active wiki/ops paths. | HIGH, 85% |
| 3 | `cache-mode` should be deferred until a measured cache baseline exists. | Active SAMOS reusable calls mostly use no cache; cache-heavy shared workflows are mostly not active call targets today. | `../wiki/.github/workflows/ci.yml:36`; `.github/workflows/ci-elixir.yml:49`; `.github/workflows/ci-rust.yml:190` | Partially supports. Useful, but not the first M1 optimization unless cache timings prove otherwise. | MED, 70% |
| 4 | `artifact-mode` is deploy/release-specific, not a general CI knob. | Active artifact use is wiki deploy archetype A; release artifacts exist in `release-rust.yml`, not current active calls. | `../wiki/.github/workflows/deploy.yml:47`; `.github/workflows/release-rust.yml:194`; `.github/workflows/release-rust.yml:212` | Supports. Keep scoped to release/static-bind paths. | HIGH, 80% |
| 5 | `clean-mode` must preserve safety cleanup even if performance tuning skips expensive refreshes. | Deploy cleanup removes secrets and credentials; the same workflow also does expensive checkout reset and `rsync --delete`. | `.github/workflows/deploy-compose.yml:122`; `.github/workflows/deploy-compose.yml:260`; `.github/workflows/deploy-compose.yml:276`; `.github/workflows/deploy-compose.yml:176` | Supports. Cleanup has safety and performance parts that should not share one blunt toggle. | HIGH, 85% |

## SCIMAT-R

| Path | Description | Reconciles SCIMAT how | Tradeoffs | Confidence | What would flip me |
| --- | --- | --- | --- | --- | --- |
| A | Add documentation-only inventory now; implement no knobs in E0D-1002. | Matches the ticket's inventory requirement and preserves existing compatibility contracts. | Does not reduce CI time by itself. | HIGH, 95% | If E0D-1002 explicitly required implementation in Linear comments not visible in repo files. |
| B | First implementation slice after this: additive `runner-profile` plus `runner-capabilities` validation for active CI workflows. | Keeps raw hosted defaults while giving Puck lanes a stable policy vocabulary. | Needs clear capability names to avoid duplicating raw labels under a new name. | HIGH, 85% | If measured timings show setup actions, not runner routing, dominate M1 everywhere. |
| C | Second implementation slice: `tool-mode` for Markdown, Jekyll, and OpenTofu, defaulting to current hosted setup. | Targets active SAMOS setup overhead without changing behavior for default callers. | Requires careful hosted fallback and self-hosted capability checks. | MED, 75% | If Puck images are not standardized enough to rely on preinstalled tools. |

KILP read: this is a policy/contract change surface, so implementation should be
reviewed in small PRs after this inventory. This artifact records the evidence
and recommended ordering without closing the product/infra policy decisions
silently.

## Ranked M1 Optimizations

1. Add `runner-profile` as an additive policy input for active CI reusables
   (`ci-baseline`, `ci-markdown`, `ci-jekyll`, `ci-opentofu`) while preserving
   raw `runner` and `ubuntu-latest` defaults. This is the lowest-risk way to
   standardize `puck-linux-arm64` and `puck-macos-arm64` usage.
2. Add `runner-capabilities` validation or detection for self-hosted profiles:
   `gh` for baseline, Homebrew for macOS Markdown/Jekyll, Docker/Compose for
   deploy, and architecture checks for Rust installers. This makes tool-mode
   decisions explicit instead of relying on accidental runner contents.
3. Add `tool-mode` to Markdown, Jekyll, and OpenTofu with default
   `hosted-setup`; let Puck callers opt into `prefer-preinstalled` only after
   runner capabilities are documented. This targets repeated Homebrew/setup
   action overhead in the active `wiki` and `ops` lanes.
4. Split `clean-mode` for `deploy-compose` into safety cleanup that always
   remains on and expensive refresh behavior that can be policy-controlled.
   Preserve decrypted env and Docker credential cleanup regardless of mode.
5. Add `cache-mode` only after baseline timing shows GitHub cache restore/save is
   a bottleneck on Puck. Initial candidates are Jekyll Bundler, Elixir Mix, and
   Rust cache behavior.
6. Add `artifact-mode` last, scoped to `deploy-compose` archetype A and
   `release-rust`. Preserve current artifact behavior for hosted release paths
   and static-bind deploys.
