# Install Solo AI Factory for Claude Code

Start from `install-factory-instructions.md` at the repository root. This
file covers only the Claude Code-specific part (step 4 there). Paths below are relative
to the target project root, or to `~` for user scope.

## Target paths

| Scope   | Agents | Skills |
|---------|--------|--------|
| Project | `.claude/agents/` | `.claude/skills/` |
| User    | `~/.claude/agents/` | `~/.claude/skills/` |

## Steps

1. **Check for a previous install.** In the chosen agents directory, look for
   files named `factory-*.md`; in the chosen skills directory, look for
   directories named `factory-*`. Never touch any other agent or skill.
   - Existing copies identical to the new ones, ignoring the `model` line:
     replace them without asking.
   - Existing copies that differ from the new ones (the user may have
     customized them): list them and ask the user before overwriting. Skip any
     the user wants to keep.
   - For every existing agent, note its current `model` value (or that it has
     none). Step 4 offers it as the default.
   - Existing `factory-*` files with no counterpart in the new set: list them
     and ask the user before deleting.
2. **Copy agents.** Copy every file in `<factory>/.ai-factory/harnesses/claude/agents/`
   into the agents directory, unchanged.
3. **Copy skills.** Copy every directory in `<factory>/.ai-factory/harnesses/claude/skills/`
   (with all files inside) into the skills directory, unchanged.
4. **Choose models.** Show the user the model for each agent: its previous
   value from step 1 if there was an install, otherwise the default in the
   table below. Ask whether to keep them or change any. Then set the `model`
   line of each installed agent to the chosen value (see [Models](#models)).
   Change nothing else in the copied files; their frontmatter is otherwise
   already in the format Claude Code expects.

## Models

- **Format:** `opus`, `sonnet`, `haiku` (each tracks the newest version), a
  full model ID such as `claude-sonnet-5-5`, or `inherit` to use the main
  conversation's model.
- **Field:** `model:` in the agent's frontmatter.

| Agent | Default |
|-------|---------|
| `factory-architect` | `opus` |
| `factory-evaluator` | `opus` |
| `factory-planner` | `sonnet` |
| `factory-coder` | `sonnet` |
| `factory-reviewer` | `sonnet` |
| `factory-verifier` | `haiku` |

To change a model later, edit the `model` line of the installed agent file. A
reinstall keeps the current value unless the user picks another one.

## Verify

List the installed agents with `/agents` and confirm all six `factory-*` agents appear. Confirm the four `factory-*` skills appear in the skills list. New files can need a session restart before they show up.
