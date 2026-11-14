---
name: git-ship
description: Ship a finished change through its branch, push, and pull request to main, then merge it when asked.
user_invocable: true
---

# Ship a Change

Every change reaches `main` through a branch and a pull request. Each step starts from
the current state: skip a step whose outcome is already true.

## 1. Assess

- `git status --short`, `git branch --show-current`, `git log --oneline main..HEAD`
- `gh pr list --head <branch> --json number,url,state`

Unrelated unstaged or untracked files stay untouched.

## 2. Branch

Branch from an up-to-date `main`. Name the branch `<type>/<slug>`, where `<type>` is
the Conventional Commit type of the main change and `<slug>` is 2-4 kebab-case words:
`feat/declared-failures`, `fix/meta-mutation`, `chore/update-dependencies`,
`refactor/split-action-file`. A release uses `chore/release-X.Y.Z`.

If work was committed on `main` by mistake and not pushed, move it: create the branch
at `HEAD`, then ask before resetting local `main` to `origin/main`.

## 3. Commit

Use `git-commit`. The branch must include the `CHANGELOG.md` entry under
`## [Unreleased]` for any change a gem user can observe (see `docs-changelog`).

## 4. Verify

`bin/ci` must pass before pushing. It runs the checks on every Ruby line of the CI
matrix and reports the lines that are not installed locally (exit code 3); say which
ones were not run.

## 5. Push and Open the Pull Request

```bash
git push -u origin <branch>
gh pr create --base main --title "<conventional commit style title>" --body "$(cat <<'EOF'
## Summary
- what changed and why

## Breaking changes
- what callers must change, or "None"

## Test plan
- [x] `bin/ci` (Ruby 3.2, 3.3, 3.4, 4.0)
EOF
)"
```

End the body with the pull request attribution line the active harness specifies.
Then wait for CI and report its result:

```bash
gh pr checks <number> --watch
```

Opening the pull request does not merge it.

## 6. Merge

Merge only when the user asks, and only with CI green. Squash by default:

```bash
gh pr merge <number> --squash --delete-branch
git switch main && git pull --ff-only && git fetch --prune
```

The pull request title becomes the subject of the squashed commit, so it must be a
valid Conventional Commit subject. When the pull request has several commits, GitHub
fills the body with their subjects: pass `--body` with what changed and why instead,
ending with the attribution trailer.

Keep a merge commit (`--merge` in place of `--squash`) when the pull request's commits
are meaningful on their own and worth keeping in the history, such as a refactoring
made of reviewable steps or a dependency update with one commit per group. A branch
with fix-up commits or work in progress is always squashed. When it isn't clear which
applies, say which one you would use and why, and let the user choose.

## Rules

- Never push to `main` directly, and never force-push `main`.
- Force-push a feature branch only with `--force-with-lease`, and only when asked or
  after a rebase the user requested.
- Publishing a release is not part of this skill: see `ops-release`.
