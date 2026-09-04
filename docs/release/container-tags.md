# Container tags and digests

Git release tags are immutable source-release markers. Docker tags serve a
different purpose: they are useful, intentionally movable discovery and
promotion names. A digest is the exact container-content identity.

Production references must use `tag@sha256:digest`. The tag communicates the
selected profile or channel to humans; the digest makes the deployed content
reproducible after a broad tag advances.

An image publisher may attach an exact source tag, a candidate/release label,
and progressively broader profile or capability aliases to one tested digest.
It must refuse to replace a source or narrow release label that already points
at another digest. Broad aliases such as `standard`, `2.8`, and `2` may advance
only after their declared validation and promotion gate.

`latest` is not a production deployment contract. Rollback changes a reviewed
deployment lock to a retained prior `tag@sha256:digest`; it never retags a
broken image.

This document records the shared policy. Existing image publishers adopt its
full promotion and lock enforcement only through separately reviewed changes.
