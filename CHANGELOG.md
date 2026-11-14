## [Unreleased]

### Changed
- `bin/check` is renamed `bin/ci`. It runs the checks on every supported Ruby version, using asdf, and `bin/ci --current` runs them on the current Ruby only.
- Development now follows agent skills in `.agents/skills` (commits, pull requests, changelog, dependencies, releases, reviews), and `AGENTS.md` is the single guide; `CLAUDE.md` points to it.

## [0.3.0] - 2026-11-14

### Breaking
- Keyword arguments to `Failure` now go to the new `Failure#details` instead of being merged into `meta`. Read `result.details[:errors]` where you used `result.meta[:errors]`.
- `FailureError#meta` is replaced by `#details` and `#failure` (the `Failure` result, set when raised by `call!`).
- `call!` raises a new `FailureError` whose `cause` is the original one.

### Added
- `failure` class method to declare an action's failures and the types of their details, plus `failures` to list them. `failure from: OtherAction` accepts the failures of another action.
- `Mu::Action.on_undeclared_failure`: `:raise` (default) or a callable receiving the action, error and details.
- A failure raised by a nested `call!` becomes the outer action's failure, with the inner `Failure` in `meta[:cause]`.
- `context:` keyword: caller information (actor, account, channel...) available as `context` in hooks and `call`, recorded in `meta[:context]`, and inherited by nested actions. `context` is now a reserved prop name.
- `record_props` class method: record every prop (default), none (`record_props false`), `only:` some or all `except:` some in `meta[:props]`.

### Changed
- An action without a `result` type accepts `nil` as its success value, and `Success()` can be called without a value. Typed results still reject `nil` unless declared with `_Nilable`.
- Minimum Ruby version raised to 3.2 (3.1 is end-of-life).
- CI now tests Ruby 3.2, 3.3, 3.4 and 4.0.
- Development lockfile updated to Literal 1.9.0, RuboCop 1.92, Steep 2.0 and RBS 4.1. This fixes the Ruby 4.0 CI job (ffi) and the `tsort` warnings on Ruby 4.0.
- CI uses `actions/checkout@v7`, which runs on Node.js 24.

### Removed
- The unused protected `result_class` method.
- Development files from the packaged gem, which now only contains `lib/mu/`, `sig/mu/` and the docs. `lib/guard/steep.rb` and the local RBS stubs for Kernel and Literal were shipped by mistake.

### Fixed
- A `meta:` hash passed by a caller is no longer modified.
- `bin/test_readme_examples` now requires `fileutils`, which is no longer loaded indirectly on Ruby 3.4+.

## [0.2.0] - 2025-10-30

### Added
- Support registering `before`, `after`, and `around` hooks by method name.
- Steep type-checking infrastructure: Steepfile, comprehensive RBS signatures for `Mu::Action`.
- Guard plugin for steep type checking.

### Changed
- `bin/check` now runs `bundle exec steep check` as part of the default contributor workflow.
- Guard automation reorganized to load the new Steep guard explicitly.
- Updated Bundler metadata to 2.7.2.

### Documentation
- Added `AGENTS.md` with contributor and workflow guidelines.

## [0.1.0] - 2025-07-23

### Added
- Initial release of Mu::Action gem
- Interactor pattern implementation with type safety using Literal gem
- Support for Success/Failure result objects with metadata tracking
- Hook system with before, after, and around hooks
- Automatic property tracking in metadata
- Custom result types with type constraints
- Comprehensive documentation and examples
