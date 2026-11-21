# Install Solo AI Factory for Cursor

Start from `install-factory-instructions.md` at the repository root. This
file covers only the Cursor-specific part (step 4 there). Paths below are relative
to the target project root, or to `~` for user scope.

## Target paths

| Scope   | Agents | Skills |
|---------|--------|--------|
| Project | `.cursor/agents/` | `.cursor/skills/` |
| User    | `~/.cursor/agents/` | `~/.cursor/skills/` |

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
2. **Copy agents.** Copy every file in `<factory>/.ai-factory/harnesses/cursor/agents/`
   into the agents directory, unchanged.
3. **Copy skills.** Copy every directory in `<factory>/.ai-factory/harnesses/cursor/skills/`
   (with all files inside) into the skills directory, unchanged.
4. **Choose models.** Show the user the model for each agent: its previous
   value from step 1 if there was an install, otherwise the default in the
   table below. Ask whether to keep them or change any. Then set the `model`
   line of each installed agent to the chosen value (see [Models](#models)).
   Change nothing else in the copied files; their frontmatter is otherwise
   already in the format Cursor expects.

## Notes

- Cursor also loads agents and skills from `.claude/`. If the Claude Code
  version is installed in the same project, Cursor uses the `.cursor/` agent
  when names collide (documented), but may list duplicate skills. Tell the user
  if both are present.

## Models

- **Format:** a Cursor model ID as shown in Cursor's model list (for example
  `grok-4.7`, `composer-2.5`), optionally with options in brackets such as
  `claude-opus-5-5[effort=high]`, or `inherit` to use the parent agent's model.
- **Field:** `model:` in the agent's frontmatter.

| Agent | Default |
|-------|---------|
| `factory-architect` | `grok-4.7` |
| `factory-evaluator` | `grok-4.7` |
| `factory-planner` | `grok-4.7` |
| `factory-coder` | `composer-2.5` |
| `factory-reviewer` | `composer-2.5` |
| `factory-verifier` | `composer-2.5` |

To change a model later, edit the `model` line of the installed agent file. A
reinstall keeps the current value unless the user picks another one.

## Verify

Confirm the six `factory-*` agents appear under Settings > Subagents and the four `factory-*` skills appear in the `/` menu. Restart Cursor if they do not show up.
