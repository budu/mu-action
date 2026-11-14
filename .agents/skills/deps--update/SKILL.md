---
name: deps-update
description: Update the gem's development dependencies or its Literal requirement, reviewing every lockfile change for supply-chain risk.
user_invocable: true
---

# Update Dependencies

The gem has one runtime dependency, `literal`. Everything else in `Gemfile.lock` is
development tooling, but the lockfile must still install on every supported Ruby.

## Baseline

Start from a clean tree on a `chore/update-dependencies` branch with `bin/check`
passing. If it fails, stop and report: don't update on top of failures.

## Resolve Under the Minimum Ruby

Run every `bundle update` under the minimum Ruby version of the gemspec
(`required_ruby_version`). Bundler only picks versions that support the Ruby it runs
on, so resolving under a newer Ruby can lock a gem the minimum cannot install. With
asdf:

```bash
ASDF_RUBY_VERSION=<minimum> bundle outdated
ASDF_RUBY_VERSION=<minimum> bundle update GEM1 GEM2 --conservative
```

## Groups

Update one group at a time, each in its own commit (`chore: update <group>`):

1. **Test and tooling**: `rspec*`, `rake`, `guard*`, `irb`.
2. **RuboCop**: new versions enable new cops (`NewCops: enable`). Autocorrect with
   `bundle exec rubocop -A`, review the diff, and keep it in the same commit.
3. **Steep and RBS**: new versions report new diagnostics. Fix signatures or add a
   narrow annotation; never loosen the Steepfile to make a failure disappear.
4. **Literal**: the lockfile pins the newest version, while the gemspec states the
   oldest supported one. Raising the gemspec requirement is a `Changed` changelog
   entry and needs the user's agreement. After updating, also run the specs against
   the lowest version the gemspec allows.

A major version of any tool is its own commit; read its changelog first.

## Supply-Chain Review

For every gem the lockfile diff adds or upgrades, including indirect ones:

```bash
git diff Gemfile.lock
curl -s "https://rubygems.org/api/v2/rubygems/GEM/versions/VERSION.json" \
  | jq '{authors, created_at, yanked, metadata}'
```

- Prefer versions released at least 7 days ago; take a younger one only for a
  security fix, and say so.
- Look closer when a gem is new to the lockfile, its authors or source repository
  changed, or the version jump doesn't match its release history. A closer look means
  `gem fetch` both versions, `gem unpack`, and `diff -ru`, reading install-time code
  (`extconf.rb`) and anything that reaches the network or the shell.

Stop and report anything suspicious. Never commit a gem you can't explain.

## Verify

After each group, run `bin/check` on every Ruby version in
`.github/workflows/main.yml`:

```bash
ASDF_RUBY_VERSION=<version> BUNDLE_FROZEN=true bundle install
ASDF_RUBY_VERSION=<version> bin/check
```

`BUNDLE_FROZEN=true` proves the committed lockfile installs as is. Watch for:

- a gem whose prebuilt platform build excludes the newest Ruby;
- deprecation warnings on the newest Ruby (for example a default gem leaving the
  standard library): fix them by updating the gem that causes them.

A Ruby version that is not installed locally is only verified by CI: say so.

## Ruby Versions

Check https://endoflife.date/api/ruby.json. Add a new Ruby line to the CI matrix once
`ruby/setup-ruby` supports it. Dropping an end-of-life line changes
`required_ruby_version`, RuboCop's `TargetRubyVersion`, the CI matrix, and `AGENTS.md`
together, and is a `Changed` changelog entry the user must approve.

## Report

End with: each updated gem as `old -> new`, supply-chain flags and their resolution,
updates held back and why, the Ruby versions verified locally, and any Ruby line that
should be added or dropped. Ship with `git-ship`.
