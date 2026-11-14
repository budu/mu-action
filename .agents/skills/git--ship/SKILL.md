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

`bin/check` must pass before pushing. For changes to the library, the gemspec, or the
lockfile, run it on every Ruby version in `.github/workflows/main.yml` when those
versions are installed locally; say which ones were not run.

## 5. Push and Open the Pull Request

```bash
git push -u origin <branch>
gh pr create --base main --title "<conventional commit style title>" --body "$(cat <<'EOF'
## Summary
- what changed and why

## Breaking changes
- what callers must change, or "None"

## Test plan
- [x] `bin/check` on Ruby X.Y
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

Merge only when the user asks, and only with CI green:

```bash
gh pr merge <number> --rebase --delete-branch
git switch main && git pull --ff-only
```

A rebase merge keeps `main` linear and preserves each Conventional Commit, which the
changelog review relies on.

## Rules

- Never push to `main` directly, and never force-push `main`.
- Force-push a feature branch only with `--force-with-lease`, and only when asked or
  after a rebase the user requested.
- Publishing a release is not part of this skill: see `ops-release`.
