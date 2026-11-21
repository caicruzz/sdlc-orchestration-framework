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

1. **Remove the previous install.** In the chosen agents directory, delete only
   files named `factory-*.md`. In the chosen skills directory, delete only
   directories named `factory-*`. Leave every other agent and skill alone.
2. **Copy agents.** Copy every file in `<factory>/.ai-factory/harnesses/cursor/agents/`
   into the agents directory, unchanged.
3. **Copy skills.** Copy every directory in `<factory>/.ai-factory/harnesses/cursor/skills/`
   (with all files inside) into the skills directory, unchanged.
4. **Do not edit the copied files.** Their frontmatter is already in the format
   Cursor expects.

## Notes

- Cursor also loads agents and skills from `.claude/`. If the Claude Code
  version is installed in the same project, Cursor uses the `.cursor/` agent
  when names collide (documented), but may list duplicate skills. Tell the user
  if both are present.

## Verify

Confirm the six `factory-*` agents appear under Settings > Subagents and the four `factory-*` skills appear in the `/` menu. Restart Cursor if they do not show up.
