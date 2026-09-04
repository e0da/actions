# SemVer rollups

The target version is chosen at release cut from the actual release delta; the
release composer validates and renders that chosen version, but never chooses
it. Build identity follows `git describe --tags --dirty --always`: a clean tag
is the release identity, while an intervening or dirty checkout retains its
derived suffix for local and preflight artifacts.

At cut time, perform one qualitative assessment of the exact changes since the
last release. Choose the SemVer version from that new work, then expand the
reader-facing notes once to the compatibility-line baseline for the chosen
version. This expansion does not reopen version selection: the earlier changes
in the wider rollup were already assessed when their own releases shipped.

Release notes have two ranges. The audit ledger is the previous published tag
to the current tag. The reader-facing GitHub summary is an upgrade rollup.

- A patch release compares the immediate preceding release to the new patch.
- A minor release `v2.5.0` compares from `v2.4.0`, even if `v2.4.2` was the
  newest patch.
- A major release `v3.0.0` compares from `v2.0.0`, even if later `v2` minors
  and patches exist.

This range is supplied explicitly to GitHub's release-notes API. It shows the
changes relevant to consumers crossing a SemVer compatibility boundary; users
who need narrower slices can use GitHub's compare UI.

Prereleases retain their configured prerelease classification. Their rollup
starts from the compatibility-line baseline of the selected target version,
unless the product explicitly declares a narrower release-candidate range.
