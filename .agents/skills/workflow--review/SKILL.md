---
name: workflow-review
description: Review a diff, branch, or pull request for actionable correctness, compatibility, and test findings.
---

# Review Code Changes

Review the requested change without modifying it unless the user separately asks for
fixes.

Understand the intended behavior, then inspect the complete diff against its base
(the pull request's target, otherwise `main`). Read the surrounding code where the
diff alone cannot establish behavior.

## What to Check

This is a library: its callers are other applications, so compatibility matters as
much as correctness.

- **Public API**: any change to `call`, `call!`, `Success`, `Failure`, `result`,
  `failure`, the hooks, `record_props`, `context`, `meta`, or the `Result` classes.
  Is it breaking? Is it marked `!` with a `Breaking` changelog entry?
- **Class-level state and inheritance**: hooks, declared failures, and prop recording
  live on the class and are copied in each feature's `inherited`. New class-level
  state must be copied too, and a subclass must not modify its parent.
- **Literal**: props that are added lazily, reserved prop names (`meta`, `context`),
  and nil handling (`_Any` rejects nil; a nil `default:` means no default).
- **Failure flow**: `Failure` raises, so code after it does not run and `after`
  hooks are skipped; nested `call!` failures become the outer failure.
- **Context**: fiber storage must be restored on every exit path.
- **Ruby versions**: syntax and standard library use must work on the minimum
  version in the gemspec.
- **Signatures and docs**: the RBS files under `sig/mu/` and the README match the code; README
  examples run (`bin/test_readme_examples`).
- **Packaging**: new files that must ship are matched by the gemspec allowlist, and
  nothing else is.
- **Tests**: specs exercise the changed behavior, including the failure branch and
  subclasses, not implementation details.

Run focused checks when they validate a finding: a spec, or a short script that
reproduces the scenario.

## Judge Findings

Validate each finding against a reachable execution path before reporting it. A
preferred style alone is not a defect. Recommend a fix for an established issue; for
an unresolved concern, name the check or the decision needed. Do not invent findings
or impose a quota.

## Report

Lead with findings ordered by severity. For each, cite the file and line, the
concrete impact, and the scenario that triggers it. Distinguish confirmed issues from
open questions. If nothing actionable remains, say so and note what was not verified.
