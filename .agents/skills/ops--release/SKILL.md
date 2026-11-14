---
name: ops-release
description: Release a new version of the gem to RubyGems and GitHub when the user asks for a release.
user_invocable: true
---

# Release the Gem

A release is public and a pushed gem version can never be replaced. Run this only
when the user asks for a release, and stop at any step that fails.

## 1. Preconditions

- `main` is up to date, clean, and its last CI run is green
  (`gh run list --branch main -L 1`).
- The `docs-changelog` review is done: `## [Unreleased]` describes every change since
  the last tag.

## 2. Choose the Version

Propose the version and wait for the user's answer. While the gem is 0.x, a release
with a `Breaking` section bumps the minor version; anything else may bump the patch.

## 3. Release Branch

On `chore/release-X.Y.Z`:

1. Rename the changelog heading: keep an empty `## [Unreleased]` and add
   `## [X.Y.Z] - YYYY-MM-DD` below it.
2. Set `VERSION` in `lib/mu/action/version.rb`.
3. Run `bundle install` under the minimum Ruby to refresh `Gemfile.lock`.
4. Run `bin/ci`.
5. Commit the three files as `chore(release): X.Y.Z`.

Ship the branch with `git-ship` and merge it once the user asks. The steps below run
on the merged `main`.

## 4. Check the Package

```bash
gem build mu-action.gemspec
tar -xOf mu-action-X.Y.Z.gem data.tar.gz | tar -tz
```

The build prints no warning, and the package contains only `lib/mu/**`, `sig/mu/**`,
`README.md`, `LICENSE.txt`, and `CHANGELOG.md`. Install it into a temporary
`GEM_HOME` and run an action from outside the repository to prove it loads.

## 5. Tag

The tag message carries the release notes, so it must hold the changelog section:

```bash
.agents/skills/ops--release/scripts/changelog-section --tag-message X.Y.Z > /tmp/vX.Y.Z.txt
git tag -a vX.Y.Z --cleanup=whitespace -F /tmp/vX.Y.Z.txt
git tag -l --format='%(contents)' vX.Y.Z   # the ### headings must be there
git push origin vX.Y.Z
```

`--cleanup=whitespace` is required: the default cleanup deletes the `###` headings as
comments.

## 6. Publish

`gem push` asks for the RubyGems MFA code, so the user runs it:

```bash
gem push mu-action-X.Y.Z.gem
```

Wait for the user to confirm, then verify with `gem list -r mu-action --exact`.

## 7. GitHub Release

```bash
gh release create vX.Y.Z --title "vX.Y.Z" --notes-from-tag --latest
gh release view vX.Y.Z --json body --jq .body
```

Delete the built `mu-action-X.Y.Z.gem` afterwards.

## Rules

- Never tag before the release commit is merged to `main` and CI is green on it.
- Never move or re-create a tag whose gem version is published, unless the user asks.
  If a release is wrong, release a new version; `gem yank` only on request.
- Upgrading the applications that use the gem is not part of a release. Their owners
  do it in their own repositories.
