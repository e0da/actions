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
