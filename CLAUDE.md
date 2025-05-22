# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

- **Run tests**: `bundle exec rspec`
- **Run linting**: `bundle exec rubocop`
- **Run all checks**: `rake` (runs both spec and rubocop)
- **Interactive console**: `bin/console`
- **Install gem locally**: `bundle exec rake install`
- **Setup development environment**: `bin/setup`

## Architecture Overview

This is a Ruby gem that provides an interactor pattern implementation
using the Literal gem for properties and type checking. The core module
`Mu::Action` is designed to be included in classes to provide:

### Core Concepts

- Actions are classes that include `Mu::Action` and implement a `call` method
- Actions can be executed via `MyAction.call(...)` or `MyAction.call!(...)`
- Results are wrapped in `Result` objects with success/failure state and metadata
- Hooks allow for cross-cutting concerns and middleware-like behavior
- Properties are automatically tracked in metadata for debugging/logging

### Dependencies

- **literal**: Core dependency for properties and type system
- **rspec**: Testing framework
- **rubocop**: Code linting and style enforcement

The gem follows standard Ruby gem conventions with lib/, spec/, and bin/
directories.
