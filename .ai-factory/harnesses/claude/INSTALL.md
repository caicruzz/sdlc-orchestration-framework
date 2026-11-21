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
   - Existing copies identical to the new ones, ignoring any `model` line:
     replace them without asking.
   - Existing copies that differ from the new ones (the user may have
     customized them): list them and ask the user before overwriting. Skip any
     the user wants to keep.
   - For every existing agent, note its current `model` value (or that it has
     none). Step 4 offers it as the default.
   - Existing `factory-*` files with no counterpart in the new set: list them
     and ask the user before deleting.
2. **Copy agents.** Copy every file in `<factory>/.ai-factory/harnesses/claude/agents/`
   into the agents directory. Step 4 sets each agent's model; change nothing
   else.
3. **Copy skills.** Copy every directory in `<factory>/.ai-factory/harnesses/claude/skills/`
   (with all files inside) into the skills directory, unchanged.
4. **Choose models.** Show the user the model for each agent: its previous
   value from step 1 if there was an install, otherwise the `model` line in
   the shipped agent file. Ask whether to keep them or change any. Then set the `model`
   line of each installed agent to the chosen value (see [Models](#models)).
   Change nothing else in the copied files; their frontmatter is otherwise
   already in the format Claude Code expects.
5. **Offer the context hooks.** Explain that `factory-build` can hand off to
   a fresh orchestrator before its context fills, and that the hooks make this
   precise: after each tool call they read the session's token usage and warn
   the orchestrator at `handoff_at_percent` (`config.md`, default 70), point it
   back to `build-state.md` after a compaction, and tell a cleared session that
   a handoff is pending. They need `python3` on `PATH`. Ask whether to install
   them. If yes:
   - Copy `<factory>/.ai-factory/harnesses/claude/hooks/factory_context.py` to
     `.claude/hooks/` (project) or `~/.claude/hooks/` (user). If a different
     file is already there, ask before overwriting.
   - Ask whether they use a 1M-token context model. If yes, append
     ` --window 1000000` to both commands below.
   - Merge these entries into `hooks` in `.claude/settings.json` (project) or
     `~/.claude/settings.json` (user). Keep every existing key and hook, and
     skip an entry whose command already runs `factory_context.py`. For user
     scope, use `python3 ~/.claude/hooks/factory_context.py` as the command.

     ```json
     {
       "hooks": {
         "PostToolUse": [
           { "hooks": [{ "type": "command", "command": "python3 \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/factory_context.py" }] }
         ],
         "SessionStart": [
           { "matcher": "startup|clear|compact", "hooks": [{ "type": "command", "command": "python3 \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/factory_context.py" }] }
         ]
       }
     }
     ```

   Without the hooks, handoff still works from the `handoff_after_rounds`
   count.

## Models

- **Format:** `opus`, `sonnet`, `haiku` (each tracks the newest version), a
  full model ID such as `claude-sonnet-5-5`, or `inherit` to use the main
  conversation's model.
- **Defaults:** the `model` line in each shipped agent file (also listed in
  the README's Supported tools table).

To change a model later, edit the `model` line of the installed agent file. A
reinstall keeps the current value unless the user picks another one.

## Verify

List the installed agents with `/agents` and confirm all six `factory-*` agents appear. Confirm the four `factory-*` skills appear in the skills list. New files can need a session restart before they show up. If you installed the context hooks, run `/hooks` and confirm the `PostToolUse` and `SessionStart` entries for `factory_context.py`.
