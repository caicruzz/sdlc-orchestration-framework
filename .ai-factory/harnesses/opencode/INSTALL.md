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
   - Existing copies identical to the new ones, ignoring any `model` line:
     replace them without asking.
   - Existing copies that differ from the new ones (the user may have
     customized them): list them and ask the user before overwriting. Skip any
     the user wants to keep.
   - For every existing agent, note its current `model` value (or that it has
     none). Step 4 offers it as the default.
   - Existing `factory-*` files with no counterpart in the new set: list them
     and ask the user before deleting.
2. **Copy agents.** Copy every file in `<factory>/.ai-factory/harnesses/opencode/agents/`
   into the agents directory. Step 4 sets each agent's model; change nothing
   else.
3. **Copy skills.** Copy every directory in `<factory>/.ai-factory/harnesses/opencode/skills/`
   (with all files inside) into the skills directory, unchanged.
4. **Choose models.** Show the user the model for each agent: its previous
   value from step 1 if there was an install, otherwise none (the shipped
   files inherit the parent session's model). Ask whether to keep them or
   change any. To pin a model, add a `model:` line directly below
   `description`; to inherit, leave it out (see [Models](#models)).
   Change nothing else in the copied files; their frontmatter is otherwise
   already in the format OpenCode expects.
5. **Offer the context plugin.** Explain that `factory-build` can hand off to a
   fresh orchestrator before its context fills, and that the plugin makes this
   precise: it measures context usage before every model request, warns the
   orchestrator at `handoff_at_percent` (`config.md`, default 70), and points
   it back to `build-state.md` after a compaction. It needs OpenCode V2. Ask
   whether to install it. If yes, copy
   `<factory>/.ai-factory/harnesses/opencode/plugins/factory-context/` to
   `.opencode/plugins/factory-context/` (project) or
   `~/.config/opencode/plugins/factory-context/` (user). If that directory
   already exists and differs, ask before overwriting. Without the plugin,
   handoff still works from the `handoff_after_rounds` count.

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
- **Default:** none. The shipped files have no `model` line, so every agent
  inherits the parent session's model.

To change a model later, add, edit or remove the `model` line in the
installed agent file. A reinstall keeps the current value unless the user picks another one.

## Verify

Confirm the six `factory-*` agents are available as subagents and the four `factory-*` skills are listed. Restart OpenCode if they do not show up. If you installed the context plugin, run `opencode plugin list` and confirm `factory-context` appears.
