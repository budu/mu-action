---
name: docs-changelog
description: Add or revise CHANGELOG.md entries for unreleased changes when a change is made or the changelog is reviewed before a release.
user_invocable: true
---

# Changelog

`CHANGELOG.md` is the source of the release notes: `ops-release` copies a version's
section into the annotated tag, and the GitHub release is created from the tag. Write
entries for someone upgrading the gem.

## Format

```markdown
## [Unreleased]

### Breaking
- What changed, then what callers must do: "Read `result.details[:errors]` where you
  used `result.meta[:errors]`."

### Added
### Changed
### Removed
### Fixed

## [0.3.0] - 2026-11-14
```

- New entries go under `## [Unreleased]`, in the same branch as the change.
- Sections appear in the order above; omit empty ones. `Breaking` comes first so it
  opens the release notes.
- One bullet per change a gem user or contributor can observe. Wrap code in
  backticks and end each bullet with a period.
- Keep development-only changes (CI, lockfile, tooling) short and under `Changed`.
- Do not add links to commits or pull requests; the file does not use them.
- Never edit the section of a released version, except to fix a factual error.

## Reviewing Before a Release

Compare the section with the history since the last tag, and add what is missing:

```bash
git log --oneline "$(git describe --tags --abbrev=0)"..HEAD
```

Every `feat`, `fix`, and breaking commit needs an entry. Check that each `Breaking`
bullet says what callers must change.

Preview what will become the release notes:

```bash
.agents/skills/ops--release/scripts/changelog-section Unreleased
```
