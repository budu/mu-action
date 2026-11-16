## [Unreleased]

### Breaking
- `call` must return the `Success(...)` it built, or call `Failure(...)`; so must an around hook, which can also return the result of the chain. Anything else raises a `TypeError`. A raw value used to be returned as the result, without the `result` type being checked, and the last expression of an around hook replaced the result. To use another action's value, write `Success(Other.call!(...))`.
- A `Failure` of another action returned from `call` becomes the failure of the action, as with `call!`: around hooks see an exception, `after` hooks are skipped and the declared failures are checked. It used to be returned as it was.
- `record_props` raises an `ArgumentError` when its first argument is not `true` or `false`, and an action raises one when it is called if `record_props` names something that is not one of its props. `record_props :email` used to record every prop, and a misspelled name in `except:` left the prop recorded.
- The context is inherited by an action called directly by a running action, and no longer by a thread or a fiber started by it: pass `context:` explicitly to an action that runs in another thread or fiber. In 0.3.0 a long-lived thread first started inside an action, such as a thread pool worker, kept that action's context for all the work it did later.
- `failure :code, from: OtherAction` declares a detail named `from`; it no longer also takes the failures of `OtherAction`. Write `failure from: OtherAction` on its own.
- Declaring a prop named `meta` or `context` raises an `ArgumentError`. In 0.3.0 such a prop was silently replaced the first time the action was instantiated.
- An around block that takes one parameter receives the chain, as an around method does. It used to receive the action. An around block that takes no parameter raises an `ArgumentError`, since it could not call the chain.

### Changed
- The message of the `FailureError` raised by `call!` or `run!` names the action and the keys of the details, as in `CreateUser failed: invalid (details: errors)`. It was the error alone. The values of the details are not shown.
- Hooks, failure checks and metadata recording no longer add methods to an action. An action gets seven methods from `Mu::Action` (`meta`, `context`, `Success`, `Failure`, `run`, `run!` and the private `initialize_meta`); the README documents them, and each can be overridden with `super`. A method of an action named `with_hooks`, `check_failure` or `resolve_method`, for example, no longer replaces part of the library.
- A subclass follows its parent class. A hook, a declared failure or a `record_props` choice added to a class after one of its subclasses was defined now applies to that subclass; each used to be copied when the subclass was defined. A parent's hooks always run before those of its subclasses.
- Literal 1.9 or later is required; 1.7 and 1.8 are no longer supported. CI only tested 1.9, and on 1.7 a prop default could not read `context`.
- The `meta` and `context` props are declared when `Mu::Action` is included, before the action's own props. They were added the first time the class was instantiated.
- The library is split into one file per feature under `lib/mu/action/`, and the RBS signatures follow the same layout. Behavior is unchanged. The internal modules `Initializer`, `MetaPropAdder`, `HookPropagator` and `FailureChecking` are replaced by `Context`, `Metadata`, `Hooks` and `Failures`. Like every constant of `Mu::Action`, these names come before top-level constants inside action classes; the README lists them.
- The README documents the order in which hooks run, and that after hooks only run when the action succeeds.
- The specs run in random order, and `bin/ci` and CI ignore focused examples.
- `bin/test_readme_examples` reports a failing example with its line in the README and the code of its block, and `bin/console` loads the classes of the README examples.
- `bin/check` is renamed `bin/ci`. It runs the checks on every supported Ruby version, using asdf, and `bin/ci --current` runs them on the current Ruby only.
- Development dependencies updated, including json 3, prism 2, erb 6 and rdoc 8. Steep and RBS stay at 2.0 and 4.1, the last versions that support Ruby 3.2.
- Development now follows agent skills in `.agents/skills` (commits, pull requests, changelog, dependencies, releases, reviews), and `AGENTS.md` is the single guide; `CLAUDE.md` points to it.

### Removed
- The RBS signatures are no longer shipped in the gem. An application could not load them: they refer to Literal declarations that exist nowhere, and they did not describe the class methods of an action. They stay in the repository for the library's own type check.
- Guard, its RSpec and RuboCop plugins, and the local Steep plugin (`lib/guard/steep.rb`) from the development tooling.

### Fixed
- `run!` on an action called from another one is treated as `call!` is: the failure is checked against the failures the outer action declares and kept in `meta[:cause]`. It used to become the outer action's failure unchecked. `run!` now goes through `run`, and raises a `FailureError` that carries the `Failure`.
- A failure detail can be named `from`, as in `failure :invalid_transition, from: Symbol, to: Symbol`. It was taken as a `from:` action, and the first such failure raised `NoMethodError`.
- `failure from:` raises an `ArgumentError` for anything that is not an action class, and actions that name each other in `from:` no longer overflow the stack.
- A top-level `Configuration` constant is no longer hidden inside action classes: the `Mu::Action::Configuration` module is gone.
- A prop default can read `context`. It used to get `nil` or the context depending on the order in which the classes were defined and called.
- The metadata of an action is initialized once. It was initialized twice for a class that includes `Mu::Action` directly.
- `record_props` accepts prop names given as strings. They were ignored, so `record_props except: %w[password]` recorded the password.
- A subclass with no props of its own runs its parent's `initialize`.
- A `meta:` hash passed by a caller is no longer modified by an `after_initialize` method.
- `around { |chain| chain.call }` no longer skips the around hooks declared after it. The block received the action, so `chain.call` ran the action directly.
- Around hooks accept lambdas that take one parameter, and methods with keyword parameters.

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
