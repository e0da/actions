# Release body

The publisher composes a release body from source-repository changes and a fixed provenance footer. By default the changes come from a GitHub-generated PR summary.

```markdown
# <product> <version> — <codename>

## Changes
<GitHub-generated source PR summary for the SemVer rollup>

## Upgrade scope
Compare: <baseline tag>...<source tag>

## Provenance
Source: <owner/repo>@<immutable commit>
Source tag: <tag>
Destination tag: <tag>
Access scope: <scope>
```

For cross-repository publication, the source and destination tags may differ.
The provenance footer is mandatory in both the created release and any
immutable-release reconciliation check.

Callers may set `release-notes-file` to a checked-in Markdown file containing product decisions such as the chosen version and its driving change. The workflow includes its contents before provenance. An unset input preserves the generated body; a configured missing or empty file fails publication. Products own validation of their version decision.

Public releases from private source repositories can set `release-notes-file-only: true` to publish user-facing changes without links to private pull requests or comparisons. This mode requires a nonempty `release-notes-file` and uses it for the Changes section. The workflow still validates the baseline tag and includes upgrade scope and provenance.
