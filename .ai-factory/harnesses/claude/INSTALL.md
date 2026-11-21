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
   - Existing copies identical to the new ones: replace them without asking.
   - Existing copies that differ from the new ones (the user may have
     customized them): list them and ask the user before overwriting. Skip any
     the user wants to keep.
   - Existing `factory-*` files with no counterpart in the new set: list them
     and ask the user before deleting.
2. **Copy agents.** Copy every file in `<factory>/.ai-factory/harnesses/claude/agents/`
   into the agents directory, unchanged.
3. **Copy skills.** Copy every directory in `<factory>/.ai-factory/harnesses/claude/skills/`
   (with all files inside) into the skills directory, unchanged.
4. **Do not edit the copied files.** Their frontmatter is already in the format
   Claude Code expects.

## Verify

List the installed agents with `/agents` and confirm all six `factory-*` agents appear. Confirm the four `factory-*` skills appear in the skills list. New files can need a session restart before they show up.
