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

## 4. Follow the harness instructions

Open the harness's `INSTALL.md` from the table above and follow it exactly. It
lists the target paths for each scope and the verification step.

## 5. Copy the shared project files

Into the target project (the repository the user wants to use the factory in),
copy without overwriting anything that already exists:

- `<factory>/.ai-factory/config.md` to `.ai-factory/config.md`
- `<factory>/.ai-factory/templates/` to `.ai-factory/templates/`

Then create `.ai-factory/projects/` and `.ai-factory/archive/` if they are
missing. Offer (do not force) to add these lines to the project's `.gitignore`:

```gitignore
.ai-factory/projects/*
.ai-factory/archive/*
```

## 6. Report

Tell the user what you installed and where, and what you skipped because it
already existed. For skipped `templates/` files, list the ones that differ from
the factory copy and offer to update them (a reinstall otherwise keeps stale
templates). Never update `config.md` this way; it holds the user's settings.
Remind the user to edit `.ai-factory/config.md` for their stack. Delete the
temporary clone if you made one.
