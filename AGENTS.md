# Repository Guidelines

## Project Structure & Module Organization
- `lib/mu/action` holds the core interactor implementation; mirror this layout when adding new components so `lib/mu/action/foo.rb` pairs with `Mu::Action::Foo`.
- `spec/` mirrors the library structure with RSpec examples; add a matching `_spec.rb` file for every public entry point.
- `sig/` provides RBS signatures that keep types honest—update them alongside code changes.
- `bin/` hosts contributor tooling (`check`, `console`, `test_readme_examples`); treat `readme_examples.rb` as generated output.

## Build, Test, and Development Commands
- `bin/check` aggregates lint, spec, and README example runs for a pre-PR smoke test. Use this instead of `rake`.
- `bundle exec rspec spec/mu/action/hook_spec.rb` executes targeted tests; leave focused specs checked in only when necessary.
- `bundle exec rubocop` enforces style; let it guide formatting instead of manual tweaks.
- `bundle exec steep check` validates Steep signatures against implementation.
- `bin/test_readme_examples --extract-only` regenerates `readme_examples.rb` after documentation updates.

## Coding Style & Naming Conventions
- Target Ruby 3.1 with two-space indentation and trailing commas only when required.
- RuboCop enforces double-quoted strings and general style—prefer fixes via `bundle exec rubocop -A` over manual edits.
- Match class and module names to their file paths (e.g., `Mu::Action::Result` lives in `lib/mu/action/result.rb`), and keep method names snake_case verbs.
- Favor small, composable interactors with explicit `prop` declarations and `Success`/`Failure` returns to stay idiomatic.

## Testing Guidelines
- Write RSpec examples that describe observable behavior; structure files as `describe Mu::Action::Feature` with nested `context` blocks.
- Cover both success and failure branches, including metadata expectations when hooks mutate state.
- Keep factories lightweight—inline doubles or `let` helpers beat global fixtures for clarity.
- Run `bundle exec rspec` locally and ensure README examples still execute via `bin/check` whenever documentation changes.

## Commit & Pull Request Guidelines
- Follow the existing Conventional Commit style (`feat:`, `chore:`, `docs:`) visible in `git log --oneline`.
- Keep commits scoped to a single concern and include any signature or README updates in the same change.
- Open pull requests with a brief summary, linked issues (if any), and mention any developer-facing changes or new scripts.
- State that `bin/check` passes; add screenshots or console snippets only when behavior changes are user-visible.
