## [Unreleased]

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
