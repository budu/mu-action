# Mu::Action Development Guide

`mu-action` is a Ruby gem: an interactor pattern built on the
[Literal](https://literal.fun) gem. Classes include `Mu::Action`, declare typed
`prop`s, implement `call`, and return `Success(value)` or `Failure(error, **details)`.
Callers use `MyAction.call(...)` for a result or `MyAction.call!(...)` for the value.
The README documents the public API.

## Directory Structure

| Path                 | Purpose                                                              |
|----------------------|----------------------------------------------------------------------|
| `lib/mu/action.rb`   | The library                                                          |
| `sig/mu/`            | RBS signatures shipped with the gem                                  |
| `sig/*.rbs`          | Local stubs for Steep (Kernel, Literal), not shipped                 |
| `spec/`              | RSpec examples, mirroring `lib/`                                     |
| `bin/`               | Contributor tooling: `ci`, `console`, `setup`, `test_readme_examples`    |
| `.agents/skills/`    | Agent skills; `.claude/skills` is a symlink to it                    |

The gemspec selects the released files with an allowlist: `lib/mu/`, `sig/mu/`,
`README.md`, `LICENSE.txt`, and `CHANGELOG.md`.

## Commands

- **All checks**: `bin/ci` runs RuboCop, RSpec, Steep and the README examples on
  every Ruby line of the CI matrix, using the newest version of each installed with
  asdf. It exits with 1 when a check fails and 3 when a line is not installed.
- **Some Ruby versions**: `bin/ci 3.2 4.0`
- **Current Ruby only**: `bin/ci --current`, or `rake`. Use it while iterating.
- **Full output**: add `--verbose`. By default a check prints its output only when it
  fails, plus any Ruby warnings when it passes.
- **One spec file**: `bundle exec rspec spec/mu/action/hooks_spec.rb`
- **Lint**: `bundle exec rubocop -A`
- **Type check**: `bundle exec steep check`
- **README examples**: `bin/test_readme_examples` runs every Ruby block of the README;
  `readme_examples.rb` is its generated output and is not committed.

CI (`.github/workflows/main.yml`) runs `bin/ci --current --verbose` on every supported
Ruby version, from the minimum in the gemspec to the newest. Its matrix is the list
of versions `bin/ci` reads.

## Quality Checklist

A change is complete when:

- `bin/ci` passes on every supported Ruby version;
- the specs cover the new behavior, including the failure branch and subclasses;
- `sig/mu/action.rbs` matches the code;
- the README documents any public API change, with an example that runs;
- `CHANGELOG.md` has an entry under `## [Unreleased]`.

## Code Style

- RuboCop decides formatting: double-quoted strings, hash shorthand syntax.
- Write for the minimum Ruby version of the gemspec.
- File paths match constant names: `Mu::Action::Foo` lives in `lib/mu/action/foo.rb`.
- Specs describe observable behavior and build their action classes inline with
  `Class.new { include Mu::Action }`.

## Workflow

- **Branches**: all development happens on a branch and reaches `main` through a pull
  request. Never commit new development on `main`.
- **Merges**: pull requests are squash-merged, except when their commits are
  meaningful on their own; those keep a merge commit.
- **Commits**: Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`,
  `chore:`), with `!` and a `BREAKING CHANGE:` footer for breaking changes.
- **Compatibility**: the gem is 0.x, but applications depend on it. Treat every
  public API change as a decision for the maintainer, and document breaking changes.
- **Repository boundary**: work only in this repository. Never change, branch, test,
  or install into the applications that use the gem; describe what they would need
  and leave it to their owners.
- **Releases**: only when the maintainer asks. `gem push` is always run by the
  maintainer.

## Skills

| Skill                   | Use it to                                                    |
|-------------------------|--------------------------------------------------------------|
| `git-commit`            | Commit with the staging and message conventions              |
| `git-ship`              | Take a branch through push, pull request, CI, and merge      |
| `docs-changelog`        | Write or review `CHANGELOG.md` entries                       |
| `deps-update`           | Update dependencies and review the lockfile changes          |
| `ops-release`           | Release a version to RubyGems and GitHub                     |
| `workflow-review`       | Review a diff, branch, or pull request                       |
| `agent-writing-skills`  | Create or revise a skill                                     |
