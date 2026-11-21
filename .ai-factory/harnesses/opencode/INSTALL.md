# Install Solo AI Factory for OpenCode

Start from `install-factory-instructions.md` at the repository root. This
file covers only the OpenCode-specific part (step 4 there). Paths below are relative
to the target project root, or to `~` for user scope.

## Target paths

| Scope   | Agents | Skills |
|---------|--------|--------|
| Project | `.opencode/agents/` | `.opencode/skills/` |
| User    | `~/.config/opencode/agents/` | `~/.config/opencode/skills/` |

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
2. **Copy agents.** Copy every file in `<factory>/.ai-factory/harnesses/opencode/agents/`
   into the agents directory, unchanged.
3. **Copy skills.** Copy every directory in `<factory>/.ai-factory/harnesses/opencode/skills/`
   (with all files inside) into the skills directory, unchanged.
4. **Choose models.** Show the user the model for each agent: its previous
   value from step 1 if there was an install, otherwise the default in the
   table below. Ask whether to keep them or change any. Then set the `model`
   line of each installed agent to the chosen value (see [Models](#models)).
   Change nothing else in the copied files; their frontmatter is otherwise
   already in the format OpenCode expects.

## Notes

- OpenCode derives each agent's name from its file name, so the files have no
  `name` field and must keep their `factory-*.md` names.
- The agents omit `model`, so they inherit the parent session's model.
- OpenCode also reads `.claude/skills/`; its own `.opencode/skills/` copy wins
  when names collide.

## Models

- **Format:** `provider/model`, optionally with a variant, for example
  `anthropic/claude-sonnet-5-5` or `anthropic/claude-sonnet-5-5#high`. OpenCode
  has no `inherit` value: to inherit the parent session's model, leave the
  `model` line out.
- **Field:** `model:` in the agent's frontmatter. The shipped files have no
  `model` line; add one directly below `description` to pin a model.

| Agent | Default |
|-------|---------|
| `factory-architect` | (none, inherits) |
| `factory-evaluator` | (none, inherits) |
| `factory-planner` | (none, inherits) |
| `factory-coder` | (none, inherits) |
| `factory-reviewer` | (none, inherits) |
| `factory-verifier` | (none, inherits) |

To change a model later, edit the `model` line of the installed agent file. A
reinstall keeps the current value unless the user picks another one.

## Verify

Confirm the six `factory-*` agents are available as subagents and the four `factory-*` skills are listed. Restart OpenCode if they do not show up.
