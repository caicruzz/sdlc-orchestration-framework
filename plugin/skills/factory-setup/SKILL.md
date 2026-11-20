---
name: factory-setup
description: >-
  Onboard a git repository to soloAIfactory: inspect the repo, propose
  .ai-factory/config.md with evidence for every value, and write only what the
  human confirms (config.md, two .gitkeep placeholders, four .gitignore lines).
  Idempotent: on a set-up repo it reports "already set up" and writes nothing.
  Use for "set up the factory", "onboard this repo to soloAIfactory",
  "configure soloAIfactory", "create .ai-factory/config.md", or /factory-setup.
---

# Factory setup (onboard a repository)

Onboard the current git repository to soloAIfactory. The skill **inspects** the repo read-only, **proposes** `.ai-factory/config.md` with the evidence behind every value, and **writes only what the human confirms**. A set-up repo holds exactly: `.ai-factory/config.md`, `.ai-factory/projects/.gitkeep`, `.ai-factory/archive/.gitkeep`, and four `.gitignore` lines. Nothing else is ever written.

**Read [`reference.md`](reference.md) (next to this file) for the detection heuristics** before step 4: the ecosystem table, command precedence and edge cases. In short: each marker file (`package.json`, `pyproject.toml` / `requirements*.txt`, `go.mod`, `Cargo.toml`, `*.sln` / `*.csproj`, `pom.xml` / `build.gradle*`) suggests a language, package manager and default commands; a hint in the request beats a task-runner target, which beats a package-manager script, which beats the command a CI config runs, which beats the ecosystem default (used only when the tool is configured or built in). Placeholder test scripts count as no test, missing lint tools are named but never installed, polyglot repos and monorepos without root scripts are asked about rather than guessed, an empty repo leaves everything unfilled, and an unfilled placeholder is always preferred to a guess.

## When to use

- The user says *set up the factory*, *onboard this repo to soloAIfactory*, *configure soloAIfactory*, *create .ai-factory/config.md*, or runs `/factory-setup`.
- Another stage skill (`factory-design`, `factory-plan`, `factory-build`) found `.ai-factory/config.md` missing or Test/Lint unfilled and steered here.
- The user asks to **re-detect** to fill optional fields left unfilled by an earlier run.

## Inputs

- The workspace (the git repository containing the current directory).
- Hints in the request, for example: "Python is the primary language", "lint is `make lint`", "apply without asking" / "Apply the proposal without asking me." (apply-without-review mode), "re-detect". There are no other arguments.

## Bundled files (read by relative path only)

| File | Use |
|---|---|
| `templates/config.md` (next to this SKILL.md) | The blank config template. Its **Commands** labels **Install**, **Test**, **Lint**, **Type check**, **Build**, **Format** are the contract with the Verifier and `factory-build`; Test and Lint are Required. |
| `reference.md` (next to this SKILL.md) | Detection heuristics, precedence, edge cases. |

Read nothing else from the installed skill directory, and never write into it.

## Definitions

- **Configured row**: its value is not empty, not whitespace, not only an HTML comment (`<!-- … -->`), and, for **Test** and **Lint** only, not `none`.
- **Unfilled row**: any row that is not configured.
- **Optional rows** (Type check, Build, Format): a *missing* row counts as intentional (the template says "remove if not applicable"); `none` on an optional row counts as a filled value.
- **Raw template**: a `config.md` in which every value is unfilled. Treat it as **absent**.
- **Set up** means exactly: `.ai-factory/config.md` exists, **Test** and **Lint** are configured, and both `.ai-factory/projects/.gitkeep` and `.ai-factory/archive/.gitkeep` exist. Unfilled optional fields (Conventions bullets, Install, Format, Architecture Notes, Project Structure, Source/Entry and so on) and declined integrations (the `.gitignore` lines) are **never gaps**.
- **The four `.gitignore` lines** (exact-line match):

  ```gitignore
  .ai-factory/projects/*
  !.ai-factory/projects/.gitkeep
  .ai-factory/archive/*
  !.ai-factory/archive/.gitkeep
  ```

## Procedure

### 1. Resolve the root

Run `git rev-parse --show-toplevel`.

- If it fails (the workspace is **not inside a git repository**), or it returns the user's **home directory** (`$HOME`), abort with exactly:

  > Run setup from inside a git repository (not your home directory)

  and **write nothing**.
- Otherwise every path below is relative to that root. Never write outside it.

### 2. Read existing state (read-only)

This step only reads; it writes nothing.

1. **`.ai-factory/config.md`**: absent, or parse it **row by row** using the definitions above (Tech Stack, Project Structure and Conventions bullets; Commands table rows; Architecture Notes). A raw template counts as absent. Remember any **unknown sections** so they are preserved untouched when writing.
2. **Placeholders**: whether `.ai-factory/projects/.gitkeep` and `.ai-factory/archive/.gitkeep` exist.
3. **`.gitignore`**: which of the four lines are present (exact-line match). If an existing rule (for example `.ai-factory/`, `.ai-factory/*` or `.ai-factory/config.md`) would ignore `.ai-factory/config.md`, **warn** in the reply that `config.md` would be ignored and agents' shared settings would not be committed. **Do not edit that rule**; the human decides.
4. **Old generated adapters**: look for files under `.claude/agents/factory-*`, `.claude/skills/factory-*`, `.cursor/agents/factory-*` and `.cursor/skills/factory-*` whose content contains the text `Generated by .ai-factory/sync.sh`. If any exist, the reply (proposal or already-set-up report) lists those paths with:

   > delete these; they override the installed factory

   **The skill deletes nothing**, and this check writes nothing.

### 3. If set up, report and stop

If the repo is **set up** and the request does **not** say "re-detect", reply:

> soloAIfactory is already set up in this repo; nothing to change

Then:

- list the unfilled optional fields and the absent `.gitignore` lines, followed by "ask me to re-detect to fill them";
- include the old-adapter list and the ignore-rule warning from step 2, if any;
- steer to `factory-design`: *"Next: describe your first feature, for example 'Run the design stage for <feature>'"*.

**Stop without writing.** No file is created or modified, by any tool including the shell. Unfilled optional fields and absent `.gitignore` lines never make a repo "not set up".

### 4. Inspect

Read `reference.md` now and apply its heuristics.

**Allowed tools only**: `git ls-files`, file reads, and `git log -20 --format=%s`. **Never run project code** (no package-manager, build, test, lint or task-runner commands; no scripts from the repo). If `git log` fails (a repo with no commits), treat it as "no commit history", not an error, and leave Commit style unfilled.

**Scope** (what may be proposed):

| State | In scope |
|---|---|
| `config.md` absent (or raw template) | Every field and the four `.gitignore` lines, plus both `.gitkeep` files |
| Request says "re-detect" (with or without "apply without asking") | Every **unfilled** field and every absent `.gitignore` line and `.gitkeep` file; filled rows appear in the proposal as `kept` |
| Otherwise (`config.md` exists but not set up) | Only the **missing required items**: unconfigured **Test** / **Lint** and any missing `.gitkeep` file. Every other row is left exactly as it is |

**A value a human wrote is never changed**: not by re-detect, not in apply-without-review mode. It changes only through an explicit human edit in step 5. Detection and the "ask" cases in `reference.md` apply **only to in-scope fields**: a configured row is shown as `kept`, is never asked about, and gets no replacement even when CI, a task runner or a script suggests a different command.

### 5. Show the proposal

Send **one message** containing:

1. A table:

   | Field | Proposed value | Evidence |
   |---|---|---|

   One row per in-scope field (plus `kept` rows on re-detect). **Evidence** is the file or line that suggested the value (for example `package.json` `scripts.test`, `Makefile` target `lint`, `.github/workflows/ci.yml` step), or `not detected; left unfilled` with the reason.
2. **File operations**: create or update `.ai-factory/config.md` (name which rows), create each missing `.gitkeep`, append the missing `.gitignore` lines (list them).
3. **For each unfilled Required row**, a warning with the right label, for example:

   > Verifier will fail as *not configured* until **Test** is set; `factory-build` will stop and ask you.

   > Verifier will fail as *not configured* until **Lint** is set; `factory-build` will stop and ask you.

   and say that design and planning still work.
4. The old-adapter list and the ignore-rule warning from step 2, if any.
5. The question: **apply / change something / cancel**.

Handling the answer:

- **apply**: go to step 6.
- **change something**: the human answers with free-text edits; apply them to the proposal and **show it again**, writing nothing yet. Repeat until apply or cancel.
- **cancel**, or **no answer yet**: no file is created or changed. Stop.

Where `reference.md` says to **ask** (polyglot repo with no task runner, monorepo with no root scripts, empty repo), ask inside this proposal message.

**Apply-without-review mode** (the request says to apply without review, for example "Apply the proposal without asking me."): show the proposal and proceed straight to step 6. Every branch that would ask the human instead **leaves the affected fields unfilled and states why**, for example:

> Test: unfilled; polyglot (Python, Go) with no task runner

Never compose commands with `&&` on your own; only a human may choose that.

### 6. Write

Only after "apply" (or in apply-without-review mode):

- **New config** (`config.md` absent or raw template): render `.ai-factory/config.md` from `templates/config.md` next to this SKILL.md. Replace each **filled** placeholder (the `<!-- … -->` comment for that row) with its value and leave every **unfilled** placeholder exactly as it is. Write not-applicable optional rows (Type check, Build, Format) as `none`.
- **Existing config**: edit it **in place**. Only the proposed rows change; every other byte of the file is unchanged (unknown sections, comments, row order, human-written values, trailing newline).
- **Placeholders**: create `.ai-factory/projects/.gitkeep` and `.ai-factory/archive/.gitkeep` if missing (empty files).
- **`.gitignore`**: append whichever of the four lines are absent (create `.gitignore` if it does not exist). Never edit or remove existing lines.

Write **nothing else** into the repo: no agents, skills, templates, scripts or tool settings (never `.claude/settings.json` or Cursor settings).

### 7. Optional smoke run

Ask: **"Run the Test and Lint commands once to confirm they work?"**

Run them only on **yes**, and report each exit code. Never run them automatically, so **never in apply-without-review mode**.

### 8. Hand off

Summarize:

- what was written (files and rows);
- what is still unfilled (with the Verifier warning for any unfilled Required row);
- that updates to soloAIfactory itself are `git pull` plus `install.sh` in the soloAIfactory clone (nothing in this repo needs updating).

End with:

> Next: describe your first feature, for example 'Run the design stage for <feature>'

## What you must not do

| Do not | Why |
|---|---|
| Write anything before the human says apply (outside apply-without-review mode) | Nothing is written without confirmation |
| Write anything on an already set-up repo without "re-detect" | Setup is idempotent |
| Change a value a human wrote | Only an explicit human edit changes it |
| Run project code while inspecting | Inspection is read-only: `git ls-files`, file reads, `git log -20 --format=%s` |
| Propose `true` (or any no-op) for Test | Test is Required; a repo with no tests sets it explicitly by the human's choice |
| Compose commands with `&&` on your own | Polyglot choices belong to the human |
| Add dependencies or install tools (for example ruff, eslint) | Name the idiomatic tool; the human decides |
| Delete old generated adapters or edit an ignore rule that hides `config.md` | Report them; the human acts |
| Write agents, skills, templates, scripts or tool settings into the repo | A target repo holds only `config.md`, two `.gitkeep` files and four `.gitignore` lines |
| Write outside the repository root, or write anything after aborting in step 1 | Never write outside the target repo |
| Run the smoke test without a yes | It is optional and opt-in |

## Verification (for the agent)

- Root resolved with `git rev-parse --show-toplevel`; not the home directory.
- On a set-up repo without "re-detect": reply contains "soloAIfactory is already set up in this repo; nothing to change" and `git status` is unchanged.
- The proposal was one message with the `| Field | Proposed value | Evidence |` table, the file operations, a warning for each unfilled Required row, and apply / change something / cancel.
- After writing: only `.ai-factory/config.md`, `.ai-factory/projects/.gitkeep`, `.ai-factory/archive/.gitkeep` and `.gitignore` changed; in an existing `config.md` only the proposed rows differ.
- Test and Lint were run only after an explicit yes.
- The hand-off ended with "Next: describe your first feature, for example 'Run the design stage for <feature>'".
