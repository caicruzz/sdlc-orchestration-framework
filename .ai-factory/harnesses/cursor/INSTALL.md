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
   - Existing copies identical to the new ones, ignoring any `model` line:
     replace them without asking.
   - Existing copies that differ from the new ones (the user may have
     customized them): list them and ask the user before overwriting. Skip any
     the user wants to keep.
   - For every existing agent, note its current `model` value (or that it has
     none). Step 4 offers it as the default.
   - Existing `factory-*` files with no counterpart in the new set: list them
     and ask the user before deleting.
2. **Copy agents.** Copy every file in `<factory>/.ai-factory/harnesses/cursor/agents/`
   into the agents directory. Step 4 sets each agent's model; change nothing
   else.
3. **Copy skills.** Copy every directory in `<factory>/.ai-factory/harnesses/cursor/skills/`
   (with all files inside) into the skills directory, unchanged.
4. **Choose models.** Show the user the model for each agent: its previous
   value from step 1 if there was an install, otherwise the `model` line in
   the shipped agent file. Ask whether to keep them or change any. Then set the `model`
   line of each installed agent to the chosen value (see [Models](#models)).
   Change nothing else in the copied files; their frontmatter is otherwise
   already in the format Cursor expects.
5. **Offer the context hooks.** Explain that `factory-build` can hand off to
   a fresh orchestrator before its context fills. Cursor reports context usage
   only when it compacts, so the hooks show the user a message at compaction
   during an active build, and tell a new chat that a handoff is pending. They
   need `python3` on `PATH`. Ask whether to install them. If yes:
   - Copy `<factory>/.ai-factory/harnesses/cursor/hooks/factory_context.py` to
     `.cursor/hooks/` (project) or `~/.cursor/hooks/` (user). If a different
     file is already there, ask before overwriting.
   - Merge these entries into `.cursor/hooks.json` (project) or
     `~/.cursor/hooks.json` (user), creating the file with `"version": 1` if it
     is missing. Keep every existing hook, and skip an entry whose command
     already runs `factory_context.py`. Project hooks run from the project
     root; for user scope, use `python3 hooks/factory_context.py` (user hooks
     run from `~/.cursor/`).

     ```json
     {
       "version": 1,
       "hooks": {
         "preCompact": [{ "command": "python3 .cursor/hooks/factory_context.py" }],
         "sessionStart": [{ "command": "python3 .cursor/hooks/factory_context.py" }]
       }
     }
     ```

   Without the hooks, handoff still works from the `handoff_after_rounds`
   count.

## Notes

- Cursor also loads agents and skills from `.claude/`. If the Claude Code
  version is installed in the same project, Cursor uses the `.cursor/` agent
  when names collide (documented), but may list duplicate skills. Tell the user
  if both are present.
- Cursor also runs Claude Code hooks from `.claude/settings.json`. If the
  Claude Code context hooks are installed in the same project, a new Cursor
  chat can get the pending-handoff note twice. Tell the user if both are
  present.

## Models

- **Format:** a Cursor model ID as shown in Cursor's model list (for example
  `grok-4.7`, `composer-2.5`), optionally with options in brackets such as
  `claude-opus-5-5[effort=high]`, or `inherit` to use the parent agent's model.
- **Defaults:** the `model` line in each shipped agent file (also listed in
  the README's Supported tools table).

To change a model later, edit the `model` line of the installed agent file. A
reinstall keeps the current value unless the user picks another one.

## Verify

Confirm the six `factory-*` agents appear under Settings > Subagents and the four `factory-*` skills appear in the `/` menu. Restart Cursor if they do not show up. If you installed the context hooks, confirm they appear in Cursor's Hooks settings.
