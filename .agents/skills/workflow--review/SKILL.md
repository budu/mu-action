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
- **Constants**: a constant defined under `Mu::Action` hides the application's
  top-level constant of the same name inside every action class. Is a new one
  needed, and is it in the README's list and in the spec that pins it?
- **Class-level state and inheritance**: hooks, declared failures, and prop recording
  are stored on the class that declares them and combined with the parent's when
  read. New class-level state must work the same way: nothing copied on `inherited`,
  a subclass follows later changes to its parent and never modifies it.
- **Literal**: the `meta` and `context` props are declared when `Mu::Action` is
  included and their names are reserved; nothing may change a class when it is
  instantiated. Nil handling: `_Any` rejects nil, and a nil `default:` means no
  default. The initializer Literal generates for a subclass with props does not call
  `super`.
- **Failure flow**: `Failure` raises, so code after it does not run and `after`
  hooks are skipped; nested `call!` failures become the outer failure.
- **Results**: `call` and the around hooks must return the `Success` the action
  built, checked by identity of its `meta`. Another action's `Failure` is raised as
  `call!` would; anything else is a `TypeError`.
- **Context**: it is kept in a fiber-local variable and restored on every exit path.
  Nothing may pass it to another thread or fiber implicitly: a thread pool worker
  would keep the context of the action that started it.
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
