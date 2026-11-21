# Install Solo AI Factory (instructions for an AI agent)

You are an AI coding agent. The user asked you to install Solo AI Factory: six
`factory-*` subagents, four `factory-*` skills, and the shared project files they
read. Follow these steps in order. Do not guess; ask the user when a step says so.

## 1. Get the factory source

If the current repository is not already a clone of
`https://github.com/caicruzz/soloAIfactory`, shallow-clone it to a temporary
directory and use that as `<factory>`:

```bash
git clone --depth 1 https://github.com/caicruzz/soloAIfactory "<tmp>/soloAIfactory"
```

Everything below reads from `<factory>/.ai-factory/`.

## 2. Identify the harness

Name the harness you are running in. Supported harnesses and their instructions:

| Harness     | Instructions                                    |
|-------------|-------------------------------------------------|
| Claude Code | `.ai-factory/harnesses/claude/INSTALL.md`       |
| Cursor      | `.ai-factory/harnesses/cursor/INSTALL.md`       |
| OpenCode    | `.ai-factory/harnesses/opencode/INSTALL.md`     |

If you are not one of these, stop and tell the user that their harness is not
supported yet. Do not adapt another harness's files.

If the user wants the factory in more than one harness, run step 4 once per
harness.

## 3. Ask for the scope

Ask the user which scope they want, and confirm the target paths before copying:

- **Project**: installs into the current repository only (the default).
- **User**: installs into the home directory, so every repository on this
  machine gets the agents and skills. Each project still needs the shared files
  from step 5.

If the user wants to run the factory in cloud agents (Claude Code on the web or
in Claude projects, Cursor cloud agents, and similar), recommend **project**
scope and tell them to commit the installed agents, skills, hooks settings and
`.ai-factory/` files to the repository. Cloud sessions start from a fresh clone,
so they see only what is committed: user-scope files on this machine never
reach them, and Claude Code cloud sessions do not install plugins a repository
enables.

## 4. Follow the harness instructions

Open the harness's `INSTALL.md` from the table above and follow it exactly. It
lists the target paths for each scope, how to choose each agent's model, and
the verification step.

## 5. Copy the shared project files

Into the target project (the repository the user wants to use the factory in),
copy without overwriting anything that already exists:

- `<factory>/.ai-factory/config.md` to `.ai-factory/config.md`
- `<factory>/.ai-factory/templates/` to `.ai-factory/templates/`

Do not create `.ai-factory/state/`: the factory skills create it on first use
as a git worktree of the state branch (`config.md` → `## State` →
`state_branch`, default `factory-state`), which needs the folder to be missing
or empty. If an existing `config.md` has no `## State` section, the skills use
the default; tell the user they can add the section from
`<factory>/.ai-factory/config.md` to change it.

Offer (do not force) to add this line to the project's `.gitignore`. Tell the
user that the factory requires it, because the state worktree must not be part
of the main checkout or of task worktrees, and that `factory-build` stops and
asks if it is missing:

```gitignore
.ai-factory/state/
```

If the project has the old folders `.ai-factory/projects/` or
`.ai-factory/archive/` with files in them, tell the user that the next factory
skill they run will offer to move that content onto the state branch.

## 6. Offer the CI workflow

The build stage opens a pull request per task, and
`.ai-factory/templates/ci/factory-checks.yml` runs the `config.md` checks on
every pull request so CI reproduces the Verifier's result. Ask the user whether
to install it (only if the project is on GitHub):

- If `.github/workflows/factory-checks.yml` already exists, leave it alone and
  say so.
- Otherwise copy the template there. If `.ai-factory/config.md` already has
  commands filled in, replace each `FACTORY_PLACEHOLDER` step's `run` with the
  matching command, delete steps whose check is not configured, and add the
  toolchain setup step for the project's stack. If `config.md` is not filled in
  yet, keep the placeholders and tell the user that the workflow fails until
  they fill it in (or ask you to, after editing `config.md`).
- Tell the user they can make `factory-checks` a required check in branch
  protection for their default branch and `factory/**` branches.

## 7. Report

Tell the user what you installed and where, and what you skipped because it
already existed. For skipped `templates/` files, list the ones that differ from
the factory copy and offer to update them (a reinstall otherwise keeps stale
templates). Never update `config.md` this way; it holds the user's settings.
Remind the user to edit `.ai-factory/config.md` for their stack. Delete the
temporary clone if you made one.
