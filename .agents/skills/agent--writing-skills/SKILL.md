---
name: agent-writing-skills
description: Create or revise repository skills that need precise triggers, concise instructions, or progressively disclosed resources.
---

# Write Repository Skills

Include only project knowledge or workflow constraints that materially change how an
agent should perform the task. Assume the agent already knows ordinary software
engineering practices.

## Decide Where Guidance Belongs

- Put instructions that apply to every repository task in `AGENTS.md`.
- Create a skill for a recognizable workflow or tool that benefits from reusable
  guidance.
- Extend an existing skill when its trigger and workflow already cover the need.
- Point to related skills by name instead of duplicating their content. When a skill
  absorbs content from `AGENTS.md`, replace the original with a reference to the skill.

## Structure

Store skills under `.agents/skills/<prefix>--<name>/` with a required `SKILL.md` and
only the supporting resources the workflow uses. `.claude/skills` is a symlink to
`.agents/skills`; never write through a second copy.

Prefixes in use:

- `agent--`: skill authoring and `AGENTS.md`
- `deps--`: dependency updates
- `docs--`: changelog and documentation
- `git--`: commits, branches and pull requests
- `ops--`: releases
- `workflow--`: review and other phases of a change

Use the double hyphen only in the directory name. Frontmatter names use a single
hyphen: `.agents/skills/ops--release/` uses `name: ops-release`.

Use `references/` for substantial conditional guidance and `scripts/` for
deterministic operations that would otherwise be rewritten. A script finds the
repository root with `git rev-parse --show-toplevel`.

Nothing under `.agents/` ships in the gem: the gemspec selects released files with an
allowlist.

## Frontmatter

```yaml
---
name: ops-example
description: Perform a specific workflow when its distinguishing condition is present.
user_invocable: true   # optional, when users call the skill directly
---
```

`description` is one sentence stating what the skill handles and the condition that
distinguishes it from nearby skills. Treat it as routing metadata: when revising a
skill, keep its `name` and `description` unless the requests that should invoke it
have changed.

## Body

Keep the purpose, non-obvious constraints, and decision boundaries in `SKILL.md`.
Prefer short examples over long prose. Use fixed sequences or absolute language only
for safety, permissions, or fragile operations such as publishing.

Before finishing, validate the frontmatter, links, and scripts. Re-read the complete
skill and remove generic advice, duplicated `AGENTS.md` policy, and stale commands.
List a new skill in the `AGENTS.md` skills section.
