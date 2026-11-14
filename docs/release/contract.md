# Release contract

`e0da/actions` owns reusable release behavior. Products own their build,
smoke-proof, access scope, formula, and the thin caller configuration.

Actions does not choose a release version. Teams decide whether to cut and
evaluate the SemVer version from the actual change at release cut; a milestone
or cycle may carry a projected version, but it is not a commitment. Candidate
identifiers such as `-pre`, `-alpha`, and `-beta.42` describe the selected
release stage without pre-allocating a future stable version.

Every published release must be built from a tag on integrated trunk, carry
checksummed immutable assets, have source-generated notes and immutable source
provenance, and prove the installed distribution surface. A retry may reconcile
missing assets, but may not replace published bytes or silently rewrite notes.

When the destination release repository differs from the source repository,
notes are generated against the source repository, not the tap. The body names
the source repository, source tag, immutable source commit, destination tag,
and configured access scope.

The reusable workflow is the enforcement owner. Its contract tests must cover
every required behavior in this document.

Monorepo callers set `source-tag-prefix` to their product namespace, such as
`mcog/`, for source tags like `mcog/v0.1.0`. The workflow removes that prefix
for the formula version and destination tag, while source release notes and
their baseline retain it. `release-tag-prefix` is a separate destination
namespace, such as `mcog-`, yielding `mcog-v0.1.0` in a shared asset repository.
Both inputs default to empty for existing callers.

Private-tap callers using `GitHubPrivateReleaseAssetDownloadStrategy` set
`homebrew-private-asset: true`. Formula updates use the published asset's API
URL and preserve the download-strategy argument. Public formulas retain the
ordinary release download URL.

For the first namespaced product tag, an absent derived previous version is treated as an initial release only when no other tag exists in that product namespace. An explicit missing baseline, or a missing baseline with existing product history, still fails.
