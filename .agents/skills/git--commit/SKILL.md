---
name: git-commit
description: Create a requested git commit using the repository's staging, verification, attribution, and message conventions.
user_invocable: true
---

# Write Commit

## Process

1. **Gather context**: `git status` (never `-uall`), `git diff`, `git diff --cached`,
   and `git log --oneline -10`.
2. **Check the branch**: new development is never committed on `main`. If the current
   branch is `main`, create a branch first (naming in `git-ship`).
3. **Preserve staged work**: treat existing staged changes as user-reviewed. When the
   index is non-empty, commit exactly what is staged unless the user asks otherwise.
4. **Plan commit boundaries**: one clear primary reason to change per commit. Keep the
   implementation with its specs, RBS signatures, README section, and `CHANGELOG.md`
   entry. Split changes that deserve independent review or rollback.
5. **Stage one logical change** with path-specific `git add <file>...`, or
   `git add -p -- <file>` when a file holds several concerns.
6. **Audit** the complete `git diff --cached` and confirm the planned subject describes
   it honestly.
7. **Verify**: run `bin/check`. If it changes files, restage only the task-owned hunks
   and audit again.
8. **Commit** with a HEREDOC message, report the hash, and stop.

## Message Rules

This repository uses Conventional Commits:

```
<type>[(scope)][!]: <summary>

Optional body: what changed and why, not how.

[BREAKING CHANGE: what callers must change]

<attribution trailer>
```

- Types: `feat` (new behavior), `fix` (bug fix), `refactor` (no behavior change),
  `docs`, `test`, `chore` (tooling, dependencies, CI, releases).
- A breaking change adds `!` after the type and a `BREAKING CHANGE:` footer.
- A release commit is `chore(release): X.Y.Z` (see `ops-release`).
- Summary: imperative mood, lower-case first word, no trailing period, at most 72
  characters for the whole first line.
- A subject that needs "and" to name unrelated outcomes is a signal to split.

```bash
git commit -m "$(cat <<'EOF'
feat: add declared failures

Actions can list the failures they return with `failure`.

Co-Authored-By: <as given by the current session>
EOF
)"
```

## Attribution

Use the co-author trailer the active harness specifies for the current session. Never
copy a trailer from an example, an earlier commit, or a previous session. If the
session gives none and the model identity is unclear, ask.

## Critical Rules

- Never use `git add -A`, `git add .`, or `git add -u`.
- Never commit new development on `main`.
- Do not push unless asked (pushing and pull requests belong to `git-ship`).
- Do not use `--no-verify`, and do not amend or rewrite commits unless asked.
- Do not commit built gems (`*.gem`), `readme_examples.rb`, or `nb-notes/`.
