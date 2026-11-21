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

1. **Remove the previous install.** In the chosen agents directory, delete only
   files named `factory-*.md`. In the chosen skills directory, delete only
   directories named `factory-*`. Leave every other agent and skill alone.
2. **Copy agents.** Copy every file in `<factory>/.ai-factory/harnesses/opencode/agents/`
   into the agents directory, unchanged.
3. **Copy skills.** Copy every directory in `<factory>/.ai-factory/harnesses/opencode/skills/`
   (with all files inside) into the skills directory, unchanged.
4. **Do not edit the copied files.** Their frontmatter is already in the format
   OpenCode expects.

## Notes

- OpenCode derives each agent's name from its file name, so the files have no
  `name` field and must keep their `factory-*.md` names.
- The agents omit `model`, so they inherit the parent session's model.
- OpenCode also reads `.claude/skills/`; its own `.opencode/skills/` copy wins
  when names collide.

## Verify

Confirm the six `factory-*` agents are available as subagents and the four `factory-*` skills are listed. Restart OpenCode if they do not show up.
