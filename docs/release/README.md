# Release management

> Canonical release-management contract for E0DA reusable Actions.
> Applies to callers of `release-homebrew-interface.yml@main`.
> Contract version: 1.

This is the single place to discover release behavior. Product repositories keep
their live caller in `.github/workflows/release.yml` and link here; they do not
copy this procedure.

- [Contract](contract.md): owners, required gates, and immutable boundaries.
- [SemVer rollups](semver-rollups.md): the reader-facing comparison range.
- [Release body](release-body.md): generated output structure and provenance.
- [Evidence](evidence.md): optional screenshots and highlights.
- [Codenames](codenames.md): deterministic human-readable release names.
- [Container tags](container-tags.md): image promotion names and digest locks.
