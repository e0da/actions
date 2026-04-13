# e0da/actions

Shared CI/CD workflows and custom actions for e0da repos.

## Workflows

### `ci-baseline.yml` — All repos

Checks that apply universally:

- **PR title**: must follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat|fix|chore|docs|refactor|test|ci: description`)
- **Branch naming**: must match `main`, `feat/*`, `fix/*`, `chore/*`, `ci/*`, `docs/*`, or `gt-*` (Graphite)
- **Secret scan**: runs [Gitleaks](https://github.com/gitleaks/gitleaks-action) on full history

> `GITLEAKS_LICENSE` secret is optional — without it Gitleaks runs in OSS mode with a rate limit.

### `ci-typescript-bun.yml` — TypeScript/Bun repos

Runs `bun install`, then skips any step whose script doesn't exist in `package.json`:

- `bun run lint`
- `bun run build`
- `bun run check` (tsc)
- `bun test` (only if test files are found)

### `ci-markdown.yml` — Markdown-heavy repos

- **Link check**: [lychee](https://github.com/lycheeverse/lychee-action) scans all `.md` files for broken external links
- **YAML frontmatter**: validates that any `---` frontmatter blocks are valid YAML

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

  # Add for markdown-heavy repos:
  markdown:
    uses: e0da/actions/.github/workflows/ci-markdown.yml@main
```

Mix and match — only include the workflows relevant to each repo.

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

1. Create `.github/workflows/ci-<type>.yml` in this repo using `workflow_call:` as the trigger
2. Update this README with what it checks and when to adopt it
3. Commit to `main` — adopters pin to `@main` so they pick it up automatically

## Custom actions roadmap

Future `actions/` directory will house composite actions for:

- Release tagging (`git describe` → GitHub Release)
- Graphite stack validation
- Bun lockfile freshness check
