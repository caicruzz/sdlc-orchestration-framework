# Design Doc

## Metadata

| Field | Value |
|---|---|
| **Project** | soloAIfactory |
| **Feature** | skills-onboarding: install soloAIfactory through each tool's native extension mechanism (a Claude Code plugin marketplace; a user-level copy for Cursor) and onboard a repository with a `factory-setup` skill instead of a CLI |
| **Author** | factory-architect |
| **Status** | approved |
| **Created** | 2026-11-19 |

## Problem Statement

Getting soloAIfactory into another repository is manual and leaves a vendored copy behind. The README Quick Start today:

```bash
cp -r .ai-factory/ /path/to/your/project/.ai-factory/
/path/to/your/project/.ai-factory/sync.sh            # writes .cursor/ and .claude/
```

followed by hand-editing `.ai-factory/config.md`. Every target repo then carries `framework/`, `templates/`, `sync.sh` and `examples/`, has to repeat the copy to upgrade, and starts with a blank config whose rows the user must work out alone. Ignore rules and `.gitkeep` files exist only in this repo.

A previous design (`.ai-factory/projects/install-cli/superseded/00-design.md`) replaced this with an npm CLI. It reached about 1,000 lines of lock files, digests, relock, overrides and npm provenance, and was set aside. Both supported tools now ship their own ways to distribute agents and skills, and onboarding is a judgment task (reading a repo and proposing commands) that suits an agent better than a deterministic CLI.

Two defects in the current framework are also fixed here, because onboarding depends on them:

- `factory-verifier.md` reads keys that the config template does not have, and treats a missing Test or Lint command as `skipped`, so an unconfigured repo can pass verification:
  ```markdown
  | Tests | `test_command` | Yes |
  | Lint | `lint_command` | Yes |
  ...
  If a config key is empty or marked `none`, skip that check.
  ```
- `.ai-factory/examples/` sits inside the shipped framework tree, and `.ai-factory/config.md` in this repo is the blank template, so this repo does not use its own factory.

## Goals

1. **Zero to `factory-design` in at most 5 user actions in Claude Code**, all inside a session: add the marketplace, install the plugin, (reload if prompted), say "set up the factory in this repo", start the first feature. No files copied by hand.
2. **Cursor in one shell command plus the same two prompts**: one user-level copy command, then "set up the factory in this repo", then the first feature.
3. **A target repo holds only `.ai-factory/config.md`, `.ai-factory/projects/.gitkeep`, `.ai-factory/archive/.gitkeep` and four `.gitignore` lines.** No install or setup step, in either tool, vendors or writes anything else (agents, skills, templates, scripts, tool settings).
4. **`factory-setup` is idempotent**: on a set-up repo (`config.md` exists, **Test** and **Lint** configured, both `.gitkeep` files exist) it reports "already set up, nothing to change", lists unfilled optional fields, and writes nothing; unfilled optional fields and declined integrations are never gaps. Otherwise it proposes only the missing required items and never changes a value a human wrote.
5. **Nothing is written without confirmation**: the human sees every proposed value with its evidence and every file to be created or changed, and says yes first, unless the request itself said to apply without review (then anything that would need a question is left unfilled, with the reason).
6. **One source of truth, no generator**: the plugin directory in this repo is what both tools load. CI checks structure and manifests on every pull request.
7. **Verifier alignment**: the Verifier reads the config template's labels, and an unfilled Required row (Test, Lint) is a `fail` marked "not configured", which `factory-build` routes to the human, not to the Coder.
8. **Upgrades never touch user files**: updating the plugin or re-running the Cursor copy replaces only the shipped user-level `factory-*` agents and skills. `config.md`, `projects/`, `archive/` and project overrides are never written by an upgrade.

## Non-Goals

- A custom CLI, npm package, lock file, version digest or drift detector.
- An overrides layer. Customization uses each tool's own precedence (see Customization below).
- Per-repo version pinning. Plugin marketplaces are registered per user, not per repo (see Trade-offs).
- Deterministic, rule-engine config detection. Detection is an agent following documented heuristics, checked by a human.
- More than one factory per git repository (for example, one per monorepo package).
- A project-level (vendored) Cursor install, and writing `.claude/settings.json` from `factory-setup` (team pinning is a README snippet).
- Future work: Cursor team-marketplace manifests (`.cursor-plugin/`), once a Teams/Enterprise user can run an acceptance import; publishing to Cursor's public marketplace or Anthropic's plugin directory (see Open Questions).
- Backwards compatibility with the `.ai-factory/framework/` + `sync.sh` layout. The project has no users.
- Supporting tools other than Claude Code and Cursor.

## Architecture Overview

### Research summary (official docs, checked 2026-11-19)

| Question | Finding | Source |
|---|---|---|
| Plugin layout | Manifest at `.claude-plugin/plugin.json` (optional; only `name` required). `skills/`, `agents/`, `hooks/` go at the plugin root, not in `.claude-plugin/`. | https://code.claude.com/docs/en/plugins-reference |
| Repo as its own marketplace | `.claude-plugin/marketplace.json` with `name`, `owner`, `plugins[]`; a plugin entry may use a relative `source` such as `"./plugin"`. Users run `/plugin marketplace add <owner>/<repo>` then `/plugin install <plugin>@<marketplace>`. `#<ref>` pins a branch or tag. | https://code.claude.com/docs/en/plugin-marketplaces, https://code.claude.com/docs/en/plugins/host-marketplace.md |
| Namespacing | Every component is namespaced under the plugin name: skill `/soloaifactory:factory-design`, agent `soloaifactory:factory-coder`. Claude can still auto-invoke a skill from its `description`. | https://code.claude.com/docs/en/plugins/components.md |
| Supporting files | Both tools resolve skill supporting files by relative path from the skill directory. | https://code.claude.com/docs/en/skills.md, https://cursor.com/docs/skills |
| Plugin agent frontmatter | Supported: `name`, `description`, `model`, `tools`, `disallowedTools`, others; `permissionMode`, `hooks`, `mcpServers` ignored. | https://code.claude.com/docs/en/plugins/components.md |
| Agent precedence | Managed > `--agents` > `.claude/agents/` > `~/.claude/agents/` > plugin, **for the same name**. A plugin agent's name is scoped (`plugin:name`), so a project `factory-coder` does **not** automatically replace `soloaifactory:factory-coder`; the docs are silent on that case. | https://code.claude.com/docs/en/sub-agents.md |
| Skill precedence | Plugin skills never collide with project or user skills: "Both load, because plugin skills are namespaced." | https://code.claude.com/docs/en/skills.md |
| Versions and updates | Computed version = `plugin.json` `version`, else marketplace entry `version`, else (relative path in a git marketplace) the commit SHA. Auto-update is **off by default** for third-party marketplaces; users run `/plugin marketplace update <name>` or turn it on in `/plugin`. Files are copied to `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`; paths outside the plugin dir are not copied. | https://code.claude.com/docs/en/plugins/loading.md |
| Team pinning | A repo's `.claude/settings.json` may set `extraKnownMarketplaces` and `enabledPlugins`. The marketplace registers only after the user trusts the folder, and **`enabledPlugins` does not install**: each contributor still runs the install once. | https://code.claude.com/docs/en/plugins/org.md |
| Validation and tests | `claude plugin validate <dir>` checks manifests and paths (`--strict` turns warnings, including a missing `version`, into failures). `claude plugin eval` runs prompt cases with scaffolded fixture workspaces and file/regex/LLM graders, as paid model calls. The eval directory must be a relative path inside the plugin (no `..`). | https://code.claude.com/docs/en/plugins-reference, https://code.claude.com/docs/en/plugin-evals.md |
| Cursor plugins | `.cursor-plugin/` manifests exist, but installing from a repo URL is an **admin flow for team marketplaces on Teams/Enterprise**. Plugin agents document only `name` and `description`. | https://cursor.com/docs/plugins, https://cursor.com/docs/reference/plugins |
| Cursor skills and agents dirs | Skills: `.cursor/skills/`, `.agents/skills/`, `~/.cursor/skills/`, plus `.claude/skills/` for compatibility. Subagents: `.cursor/agents/`, `.claude/agents/`, user equivalents; project wins over user, `.cursor/` wins over `.claude/`. Frontmatter: `name`, `description`, `model`, `readonly`, `is_background`. | https://cursor.com/docs/skills, https://cursor.com/docs/subagents |

**Where the research contradicts the intended direction:**
- *Project agents override plugin agents through precedence*: not automatically, because the names differ. The skills therefore pick the agent by name: a bare `factory-<name>` override if one exists, else the plugin's agent (see API Surface).
- *Team pinning prompts teammates to install*: it registers the marketplace after folder trust, but each contributor still runs one install command. It saves only the `marketplace add` step, so it is a README snippet, not a setup step.
- *Cursor has an equivalent marketplace*: only for Teams/Enterprise admins. For individuals the simplest path is a documented copy into `~/.cursor/`.
- *Templates addressed through a plugin-root variable*: `${CLAUDE_PLUGIN_ROOT}` is substituted only by Claude Code, and a subagent reading a file outside the workspace is undocumented in Cursor. The skill therefore reads its bundled template (a relative supporting file) and pastes the content into the subagent prompt.

### Key decisions

1. **The plugin directory is the single source of truth, and nothing is generated.** `plugin/` holds `agents/` and `skills/`. Claude Code loads it through the marketplace. Cursor loads the same files, copied into `~/.cursor/`. `sync.sh` and the committed `.claude/` and `.cursor/` adapters are deleted.
2. **One agent file serves both tools.** The only adapter difference `sync.sh` handled was read-only mapping. Each read-only agent now carries both forms in its frontmatter: `readonly: true` (read by Cursor) and `tools: Read, Grep, Glob[, Bash]` (read by Claude Code). Each tool ignores the other's field. `scripts/check.sh` enforces that the two agree, which replaces the generator.
3. **Each template lives in the one skill that uses it**, under `skills/<skill>/templates/`. The skill reads it and either pastes its content into the subagent prompt (Architect, Planner) or applies it itself when persisting a returned report (Evaluator, Reviewer, Verifier). Agents never read template files.
4. **`factory-setup` is a skill, not a script.** It inspects the repo, proposes `config.md` with evidence, confirms, writes, and steers to `factory-design`.
5. **No `version` field. Every commit on `main` is a new version**, identified by the marketplace repo's commit SHA, including commits that touch only README, CI or examples. `main` is always releasable (CI-gated PRs). Optional `vX.Y.Z` tags mark milestones and give users a `#vX.Y.Z` ref to freeze on.

### Repository layout after the change

```
.claude-plugin/marketplace.json      # Claude Code marketplace: one plugin, source ./plugin
plugin/                              # THE source of truth (plugin root)
  .claude-plugin/plugin.json
  agents/factory-{architect,evaluator,planner,coder,reviewer,verifier}.md
  skills/
    factory-setup/   SKILL.md  reference.md  templates/config.md
    factory-design/  SKILL.md  templates/design.md  templates/evaluation.md
    factory-plan/    SKILL.md  templates/epic.md  templates/task.md
    factory-build/   SKILL.md  templates/review.md  templates/verify.md
    factory-archive/ SKILL.md  reference.md
  evals/                             # factory-setup eval cases (must sit inside the plugin; inert unless run)
examples/oauth2/...                  # moved out of .ai-factory/ (not shipped)
scripts/check.sh                     # structure, manifest and reference checks
.github/workflows/check.yml
.cursor/agents -> ../plugin/agents   # symlinks: Cursor contributors load the working tree
.cursor/skills -> ../plugin/skills
.ai-factory/                         # this repo, set up exactly like a target repo
  config.md                          # filled for this repo (dogfood)
  projects/.gitkeep
  archive/.gitkeep
README.md
```

Claude Code contributors dogfood with `claude --plugin-dir ./plugin`. A session-only plugin replaces a same-named installed marketplace plugin (loading.md, "Name conflicts"). This repo deliberately does **not** declare itself as a project marketplace in `.claude/settings.json`. Marketplaces are registered per user by name, so a project-scoped `soloaifactory` with a `directory` source would replace a contributor's GitHub-sourced `soloaifactory` in every project.

### Onboarding flow: Claude Code

1. `/plugin marketplace add <owner>/<repo>`
2. `/plugin install soloaifactory@soloaifactory` (user scope by default), then `/reload-plugins` if prompted.
3. In the target repo: *"Set up the factory in this repo"* (or `/soloaifactory:factory-setup`). The skill proposes, the human confirms, the skill writes.
4. *"Run the design stage for <feature>"*, which runs `factory-design`.
5. Optional: turn on auto-update for the `soloaifactory` marketplace in `/plugin` → Marketplaces. Otherwise update with `/plugin marketplace update soloaifactory`.

Teams: the README's Team section gives a `.claude/settings.json` snippet (Data Model 4) to commit by hand. After trusting the folder, each teammate still runs `claude plugin install soloaifactory@soloaifactory --scope project` once.

### Onboarding flow: Cursor

1. Run once (user level):
   ```bash
   tmp="$(mktemp -d)" && git clone --depth 1 https://github.com/<owner>/<repo>.git "$tmp" \
     && mkdir -p ~/.cursor/agents ~/.cursor/skills \
     && rm -rf ~/.cursor/agents/factory-*.md ~/.cursor/skills/factory-* \
     && cp "$tmp"/plugin/agents/*.md ~/.cursor/agents/ \
     && cp -R "$tmp"/plugin/skills/. ~/.cursor/skills/ \
     && rm -rf "$tmp"
   ```
2. Reload the window.
3. *"Set up the factory in this repo"*.
4. *"Run the design stage for <feature>"*.

Upgrade: re-run step 1. It replaces exactly the `factory-*` files under `~/.cursor/` (so files removed upstream do not linger) and writes nothing in any repo. Overrides live in the project (see Customization).

### `factory-setup` skill specification

**Trigger** (frontmatter `description`): "set up the factory", "onboard this repo to soloAIfactory", "configure soloAIfactory", "create .ai-factory/config.md", or `/soloaifactory:factory-setup`. Other skills steer here when `.ai-factory/config.md` is missing (see below).

**Inputs**: the workspace and any hints in the request (for example "Python is the primary language", "lint is `make lint`", "apply without asking", "re-detect"). No other arguments.

**Procedure**

1. **Resolve the root**: `git rev-parse --show-toplevel`. If not a git repo, or the root is the home directory, abort with "Run setup from inside a git repository (not your home directory)" and write nothing.
2. **Read existing state** (read-only):
   - `.ai-factory/config.md`: absent, or parsed row by row. A row is *configured* when its value is not empty, whitespace or only an HTML comment, and, for **Test** and **Lint**, not `none`. A missing optional row (Type check, Build, Format) is intentional (the template says "remove if not applicable"); `none` on an optional row is a filled value. A file in which every value is unfilled (the raw template) is treated as absent. Unknown sections are preserved untouched.
   - `.ai-factory/projects/.gitkeep`, `.ai-factory/archive/.gitkeep`.
   - The four `.gitignore` lines (exact-line match). If an existing rule such as `.ai-factory/` would ignore `config.md`, warn and do not edit that rule.
3. **If the repo is set up** (`config.md` exists, Test and Lint configured, both `.gitkeep` files exist) and the request does not say "re-detect": report "soloAIfactory is already set up in this repo; nothing to change", list unfilled optional fields and absent `.gitignore` lines ("ask me to re-detect to fill them"), steer to `factory-design`, and stop **without writing**. Unfilled optional fields (Conventions bullets, Install, Format, Architecture Notes, Source/Entry and so on) and declined integrations (the `.gitignore` lines) are never gaps.
4. **Inspect the repo** (read-only, using `git ls-files`, file reads and `git log -20 --format=%s`; never run project code) using the heuristics in `reference.md` (summarized below). Scope: every field and the `.gitignore` lines when `config.md` is absent; on "re-detect", every *unfilled* field and absent `.gitignore` line, with filled rows shown in the proposal as `kept` (a value a human wrote changes only through an explicit human edit, never through re-detect, with or without "apply without asking"); otherwise only the missing required items (Test, Lint, `.gitkeep` files).
5. **Show the proposal** as one message:
   - a table `| Field | Proposed value | Evidence |`, where evidence is the file or line that suggested the value, or "not detected; left unfilled" with the reason;
   - the file operations: create/update `config.md` (which rows), create each `.gitkeep`, append the `.gitignore` lines;
   - a warning for each unfilled Required row: "Verifier will fail as *not configured* until **Lint** is set; `factory-build` will stop and ask you." Design and planning still work.
   Then ask: apply / change something / cancel. "Change something" takes free-text edits and re-shows the proposal.
   **Apply-without-review mode** (the request said to apply without review): show the proposal and proceed. Every branch that would ask the human (polyglot with no task runner, monorepo with no root scripts, empty repo) instead leaves the affected fields unfilled and states why ("Test: unfilled; polyglot (Python, Go) with no task runner").
6. **Write**: render `config.md` from `templates/config.md` next to this SKILL.md, replacing each filled placeholder and leaving unfilled placeholders as they are. For an existing file, edit only the proposed rows. Create the `.gitkeep` files and `.gitignore` lines.
7. **Optional smoke run**: "Run the Test and Lint commands once to confirm they work?" Run them only on yes, and report the exit codes. Never run them automatically (so never in apply-without-review mode).
8. **Hand off**: summarize what was written and what is still unfilled, suggest turning on auto-update (Claude Code), and steer: *"Next: describe your first feature, for example 'Run the design stage for <feature>'"* (`factory-design`).

**Detection heuristics** (`reference.md`; the agent proposes, the human decides)

| Marker | Language / PM | Test | Lint | Type check | Build |
|---|---|---|---|---|---|
| `package.json` | TS if `tsconfig.json`, else JS; PM from lockfile (`pnpm-lock.yaml`, `yarn.lock`, `bun.lock`, else npm) | `<pm> test` if `scripts.test` is real | `<pm> run lint` if script | `<pm> run typecheck` if script, else `npx tsc --noEmit` if `tsconfig.json` | `<pm> run build` if script |
| `pyproject.toml` / `requirements*.txt` | Python; `uv.lock`→uv, `poetry.lock`→poetry, else pip | `pytest` (prefixed `uv run`/`poetry run`) if pytest configured, referenced, or `tests/` has `.py` | `ruff check .` if ruff configured, else `flake8` if configured | `mypy .` if configured | `none` |
| `go.mod` | Go | `go test ./...` | `golangci-lint run` if `.golangci.y*ml`, else `go vet ./...` | `none` | `go build ./...` |
| `Cargo.toml` | Rust / cargo | `cargo test` | `cargo clippy -- -D warnings` | `none` | `cargo build` |
| `*.sln` / `*.csproj` | C# / dotnet | `dotnet test` | `dotnet format --verify-no-changes` | `none` | `dotnet build` |
| `pom.xml` / `build.gradle*` | Java/Kotlin / maven or gradle | `mvn test` / `./gradlew test` | `./gradlew check` if configured, else unfilled | `none` | `mvn package` / `./gradlew build` |

Precedence for each command, highest first: a hint in the request; a task-runner target (`Makefile`, `justfile`, `Taskfile.yml`, `tox.ini`, `noxfile.py`) named test/lint/typecheck/build; a package-manager script; the plain command a CI config runs (`.github/workflows/*.yml`, `.gitlab-ci.yml`); the ecosystem default above, used only when the tool is configured or built in.

Edge cases (each "ask" becomes "leave unfilled with the reason" in apply-without-review mode):
- **No tests / `npm init` placeholder**: a `scripts.test` containing `no test specified` (case-insensitive) or consisting of `echo …` followed by `exit 1` counts as no test. Test is Required, so it stays unfilled with the Verifier warning until the human sets it (for example `true`; setup never proposes that).
- **No lint configured**: propose a zero-config built-in only where one exists (`go vet ./...`, `cargo clippy`). Otherwise leave Lint unfilled and name the idiomatic tool (ruff, eslint) without adding dependencies.
- **Polyglot**: if a task-runner target covers everything, use it. If exactly one ecosystem has a test signal, it is primary. If several do, ask the human to pick one or compose with `&&`; never choose silently. List every detected ecosystem under Tech Stack and Architecture Notes.
- **Tooling-only `package.json`** (for example Prettier or husky in a Python repo): no Node test signal, so Node is not primary.
- **Monorepo workspaces** (`pnpm-workspace.yaml`, `workspaces`, turbo, nx): prefer root scripts (`pnpm -r test`, `turbo run test`); if there are none, ask.
- **Empty repo / no markers**: every value unfilled. Ask the human for the language and commands.
- **Conventions**: Commit style is set to Conventional Commits if most of the last 20 subjects match `^\w+(\(.+\))?!?:`. Code style comes from formatter config files. Naming, test naming and import style stay unfilled unless obvious. Prefer an unfilled placeholder to a guess.
- **Not-applicable optional rows** are written as `none`, which the Verifier treats as `skipped`.

### Template location and reference strategy

| Template (old path) | New location | Consumer | How it is used |
|---|---|---|---|
| `.ai-factory/config.md` (blank) | `plugin/skills/factory-setup/templates/config.md` | `factory-setup` | Skill reads it and renders the target `config.md` |
| `.ai-factory/templates/design.md` | `plugin/skills/factory-design/templates/design.md` | `factory-design` → Architect | Skill pastes its content into the Architect prompt |
| `.ai-factory/templates/evaluation.md` | `plugin/skills/factory-design/templates/evaluation.md` | `factory-design` | Skill formats the Evaluator's returned report with it when persisting; the Evaluator gets no template |
| `.ai-factory/templates/epic.md`, `task.md` | `plugin/skills/factory-plan/templates/` | `factory-plan` → Planner | Skill pastes both into the Planner prompt |
| `.ai-factory/templates/review.md`, `verify.md` | `plugin/skills/factory-build/templates/` | `factory-build` | Skill applies them when persisting the reports; the Reviewer and Verifier get no template |

Rule written into each skill: *"Templates are in `templates/` next to this SKILL.md. Paste the template's full content into the subagent prompt under a `Template` heading"* (for reports: *"shape the returned report with it when persisting"*). No plugin-root variable, absolute path or out-of-workspace read is needed, in either tool. The Architect and Planner change from "read `.ai-factory/templates/X.md`" to "follow the template in your prompt; if there is none, stop and say to run the `factory-<stage>` skill". The Reviewer and Verifier drop their template references. `factory-archive` stops referring to `epic.md`: the graph shape comes from the project's own `01-epic.md`, and the "never delete `.ai-factory/templates/`" rule is removed because target repos no longer have that directory.

### Customization and precedence (README section)

Customization goes in this order, cheapest first:
1. **Project rules**: `config.md` → Conventions and Architecture Notes. Every agent reads it. This covers most needs ("always use the repository pattern").
2. **Override one agent**: Claude Code: `.claude/agents/factory-coder.md` (or `~/.claude/agents/`) with `name: factory-coder`. The skills prefer a bare-named agent over the plugin's `soloaifactory:factory-coder` (see API Surface). Cursor: project level only, `.cursor/agents/factory-coder.md` or `.claude/agents/factory-coder.md` (Cursor reads both, so one file serves both tools); project beats user. User-level `~/.cursor/**/factory-*` is replaced on upgrade.
3. **Eject** (to change skills or templates): copy `plugin/skills` and `plugin/agents` into the project's `.claude/` (or `.cursor/`) and, in Claude Code, set `"soloaifactory@soloaifactory": false` under `enabledPlugins` in `.claude/settings.json`. From then on the project owns its copy and upgrades no longer apply.

Upgrades never write any of these files.

### Verifier and build alignment (carried over)

- `factory-verifier.md` Checks table becomes:

  | Check | Config label (Commands table) | Required |
  |---|---|---|
  | Tests | **Test** | Yes |
  | Lint | **Lint** | Yes |
  | Type check | **Type check** | No |
  | Build | **Build** | No |

  A row is *not configured* when it is missing, empty, `none`, or only an HTML-comment placeholder. Required and not configured: status `fail`, output "not configured: set **<Label>** in `.ai-factory/config.md` (human action required)", command not run. Optional and not configured: `skipped`. **Install** and **Format** are never run.
- **Verdict Rules**: "**Pass**: every Required check is configured and every configured check exits 0. **Fail**: any check exits non-zero, **or any Required check is not configured**." The Important bullet "If a check command is missing from config, note it as `skipped`" becomes "An optional check that is not configured is `skipped`; a Required check that is not configured is `fail` (not configured)."
- **`factory-build` precondition 3**: "`.ai-factory/config.md` present **with Test and Lint filled**; otherwise stop and ask the human (suggest re-running `factory-setup`)."
- **`factory-build` Step C table**: a new row goes **first after `pass | pass`**: `anything | fail, and a failed check is *not configured*` → **stop and ask the human to fill the command; do not append to the task file or re-invoke the Coder.** A sentence under the table states that this row **overrides every other row**.
- **`factory-design` and `factory-plan` preconditions**: if `.ai-factory/config.md` is missing, offer to run `factory-setup` first.

### Testing strategy

1. **Every pull request (free, deterministic)**: `.github/workflows/check.yml` runs:
   - `scripts/check.sh` (bash + `jq`):
     - both manifests parse; `plugin.json` says `name: soloaifactory`; the marketplace points at `./plugin`; neither sets `version`;
     - every `skills/<d>/SKILL.md` has frontmatter `name: <d>` and a `description`; every `templates/*.md` a SKILL.md names exists; no agent file mentions `templates/`;
     - every agent has `name` equal to its file basename; `readonly: true` if and only if `tools:` is present; read-only `tools` never include Edit/Write; Bash appears only for factory-reviewer and factory-verifier;
     - `git grep` finds no `.ai-factory/templates`, `.ai-factory/framework`, `.ai-factory/examples` or `sync.sh` in tracked files, excluding `scripts/check.sh`, `.ai-factory/projects/`, `.ai-factory/archive/` and the README stale-`sync.sh` Troubleshooting line;
     - verifier contract: the Verifier's labels are a subset of the Commands labels in `templates/config.md`; its Required column is `Yes` exactly for the rows marked Required there; its Verdict Rules contain "not configured"; no line matches an unconditional skip (`missing from config.*skipped` without "optional"); `factory-build` Step C's second data row contains "not configured" and the override sentence is present;
     - the `.cursor/agents` and `.cursor/skills` symlinks resolve into `plugin/`.
   - `shellcheck scripts/*.sh plugin/evals/*/*.sh`.
   - `claude plugin validate .` and `claude plugin validate ./plugin` (Claude Code installed via npm in the job). Not `--strict`, because a missing `version` is a warning by design.
2. **Behavioural evals for `factory-setup` (paid, on demand before merging changes to setup)**: `plugin/evals/` holds `claude plugin eval` cases. They cannot live at the repo root (the eval directory must be inside the plugin), so they ship in the plugin cache as inert text (scaffold scripts run only with `--scaffold`). Each case has a `scaffold_script` that builds a fixture repo, the prompt "Set up the factory in this repo. Apply the proposal without asking me." (unless noted), and cost-free graders (`file_exists`, `regex` on file content or reply, `tool_used`):
   - `node-npm-init`: placeholder test script → Test unfilled, warning present;
   - `python-uv-ruff` → `uv run pytest`, `ruff check .`;
   - `go-plain` → `go test ./...`, `go vet ./...`;
   - `polyglot-makefile` → `make test`, `make lint`;
   - `polyglot-no-runner` (Python + Go, no task runner) → Test left unfilled with a stated reason, no `&&` composition;
   - `python-with-prettier-package-json` → Python primary;
   - `empty-repo` → all unfilled, `.gitkeep` files and `.gitignore` lines written;
   - `already-set-up`: Test and Lint filled, both `.gitkeep` files, typical unfilled optional rows (Conventions, Install, Format, Architecture Notes) and no `.gitignore` lines → reply says nothing to change; `tool_used` Write/Edit `max: 0`; an anchored full-content regex matches the scaffolded `config.md`;
   - `partial-lint-gap` → only Lint is proposed; an anchored full-content regex asserts every other row is unchanged;
   - `confirmation-gate`: prompt "Set up the factory in this repo." (no apply) → `file_exists` `exists: false` for `config.md` and both `.gitkeep` files.
   Run with `claude plugin eval ./plugin --scaffold --trust-plugin --ablation none --max-cost-usd <cap>`.
3. **Manual acceptance run (documented in README → Contributing)**: in both Claude Code (`--plugin-dir ./plugin`) and Cursor (symlinked `.cursor/`), run setup on two eval fixtures, confirm the proposal, re-run and check the reply says already set up and `git status` is clean, then run `factory-design` far enough to confirm the Design Doc follows `design.md`'s headings. Also check these documentation gaps:
   - with `.claude/agents/factory-coder.md` present, `factory-build` invokes the bare-named override;
   - Cursor ignores `tools:` and Claude Code ignores `readonly:`;
   - Cursor follows the symlinked directories.
4. **Dogfood (last, once `factory-setup` exists)**: run `factory-setup` on this repo to produce `.ai-factory/config.md`, then use the factory for this repo's own features.

### Trade-offs versus the superseded CLI

| Lost | Why it is acceptable |
|---|---|
| Per-repo version pinning (lock file) | Marketplaces are per user. A user can freeze with `/plugin marketplace add <owner>/<repo>#vX.Y.Z`. Agents and skills are prompts: a newer version changes behaviour, not the contents of `config.md`, so no repo state breaks. |
| Deterministic, unit-tested detection | Detection is advisory and always confirmed by a human, with evidence shown. Evals catch regressions in the cases that matter. Judgment handles edge cases (polyglot, monorepo) that rules handled poorly. |
| Unattended CI install and onboarding | Mostly kept for Claude Code: `claude plugin marketplace add`/`install` are scriptable, a seed directory serves containers (org.md), and "apply without asking" lets `claude -p` run setup (uncertain fields stay unfilled). Cursor has no unattended path. |
| Drift detection (digests, `status`) | Claude Code tracks the installed version (SHA) itself. Cursor copies can go stale silently. Mitigation: re-run the copy. There is nothing to drift in the repo because nothing is vendored. |
| Uninstall command | `/plugin uninstall`; Cursor: delete the `factory-*` files. Repo files are the user's to keep. |

Gained: about 1,000 lines of design and a CLI codebase not built; no generator; one copy of every prompt; native update UX; onboarding that explains its reasoning.

## Data Model Changes

**1. `.claude-plugin/marketplace.json`** (repo root)
```json
{
  "name": "soloaifactory",
  "owner": { "name": "soloAIfactory" },
  "description": "soloAIfactory: an AI software factory with human quality gates",
  "plugins": [
    { "name": "soloaifactory", "source": "./plugin", "description": "Design, plan, build and archive stages with Architect, Evaluator, Planner, Coder, Reviewer and Verifier agents" }
  ]
}
```

**2. `plugin/.claude-plugin/plugin.json`** (no `version`, by decision 5)
```json
{ "name": "soloaifactory", "description": "…", "author": { "name": "soloAIfactory" }, "repository": "https://github.com/<owner>/<repo>", "license": "<license>" }
```

**3. Agent frontmatter** (canonical, both tools). The `shell` key is dropped.
```yaml
---
name: factory-reviewer
description: >
  Reviews code quality against task requirements. …
model: inherit
readonly: true                 # Cursor
tools: Read, Grep, Glob, Bash  # Claude Code; Evaluator: Read, Grep, Glob
---
```
Writable agents (Architect, Planner, Coder) have neither `readonly` nor `tools`.

**4. README Team snippet** for a target repo's `.claude/settings.json` (committed by a human; no skill writes it):
```json
{
  "extraKnownMarketplaces": {
    "soloaifactory": { "source": { "source": "github", "repo": "<owner>/<repo>" } }
  },
  "enabledPlugins": { "soloaifactory@soloaifactory": true }
}
```

**5. Target repo `.gitignore` lines** (appended if absent):
```gitignore
.ai-factory/projects/*
!.ai-factory/projects/.gitkeep
.ai-factory/archive/*
!.ai-factory/archive/.gitkeep
```

**6. `config.md` template**: content unchanged, moved to `plugin/skills/factory-setup/templates/config.md`. Labels (**Test**, **Lint**, **Type check**, **Build**, **Install**, **Format**) are now the contract between `factory-setup`, the Verifier and `factory-build`. Test is Required: a repo with no tests must set it explicitly (the human's choice, for example `true`).

**7. This repo's `.ai-factory/config.md`** (filled): Language Markdown, Bash, JSON; Runtime bash 3.2+; Framework Claude Code plugin + Cursor skills/subagents; Package Manager none; Test `scripts/check.sh`; Lint `shellcheck scripts/*.sh plugin/evals/*/*.sh && claude plugin validate . && claude plugin validate ./plugin`; Type check and Build `none`; Install `none`; Commit style Conventional Commits. Lint needs the `claude` CLI, so Cursor-only contributors' Verifier runs fail Lint without it (documented in Contributing).

## API Surface Changes

There is no programmatic API. The user-facing surface is:

| Surface | Before | After |
|---|---|---|
| Install (Claude Code) | `cp -r` + `sync.sh` | `/plugin marketplace add <owner>/<repo>`; `/plugin install soloaifactory@soloaifactory` |
| Install (Cursor) | `cp -r` + `sync.sh --target cursor` | User-level copy command |
| Onboard repo | edit `config.md` by hand | `factory-setup` skill ("set up the factory in this repo") |
| Skill names | `/factory-design` | Claude Code `/soloaifactory:factory-design` (auto-invoked by description as before); Cursor `/factory-design` |
| Agent IDs | `factory-coder` | Claude Code `soloaifactory:factory-coder` (or a bare `factory-coder` override); Cursor `factory-coder` |
| Update | re-copy + `sync.sh` | `/plugin marketplace update soloaifactory` or auto-update; Cursor re-runs the copy command |

**Subagent selection contract** (replaces the "Invoking subagents" section in all four stage skills, which currently reads "The subagents live in `.cursor/agents/` and `.claude/agents/`; both are generated from `.ai-factory/framework/agents/` by `.ai-factory/sync.sh`"):

```markdown
## Invoking subagents
Wherever this skill says *invoke the `factory-<name>` subagent*:
- **Cursor**: delegate by name, e.g. `/factory-<name> <input>`.
- **Claude Code**: call the Agent tool. For `subagent_type`, use `factory-<name>` if the
  Agent tool lists an agent with exactly that name (a project or user override);
  otherwise use the plugin agent, listed as `soloaifactory:factory-<name>`.
Pass only the inputs this skill names (paths, task IDs, inlined template content).
```

**Template contract**: the Architect prompt includes `.ai-factory/projects/<slug>/00-design.md` (output) and the full content of `design.md`. The Planner prompt includes the Design Doc path and the full content of `epic.md` and `task.md`. The Evaluator, Reviewer and Verifier prompts include no template; `factory-design` and `factory-build` shape their returned reports with `evaluation.md`, `review.md` and `verify.md` when persisting. The Verifier prompt still carries the task ID and no task prose.

## File Impact Map

| File | Action | Description |
|---|---|---|
| `.claude-plugin/marketplace.json` | create | Claude Code marketplace, one plugin `./plugin` |
| `plugin/.claude-plugin/plugin.json` | create | Claude plugin manifest, no `version` |
| `plugin/agents/factory-architect.md` | move + modify | From `.ai-factory/framework/agents/`; follows the template inlined in its prompt instead of reading `.ai-factory/templates/design.md` (lines 21, 33); stops if none was included |
| `plugin/agents/factory-evaluator.md` | move + modify | Add `tools: Read, Grep, Glob`; drop `shell` |
| `plugin/agents/factory-planner.md` | move + modify | Follows `epic.md`/`task.md` inlined in its prompt (lines 41, 43, 122) |
| `plugin/agents/factory-coder.md` | move | Unchanged content |
| `plugin/agents/factory-reviewer.md` | move + modify | Add `tools: Read, Grep, Glob, Bash`; drop `shell`; drop the `review.md` reference (line 55) |
| `plugin/agents/factory-verifier.md` | move + modify | Add tools; drop `shell`; label-keyed Checks table, not-configured fail, Verdict Rules, Important bullet; drop the `verify.md` reference (line 53) |
| `plugin/skills/factory-setup/SKILL.md` | create | New onboarding skill (procedure above, under 500 lines) |
| `plugin/skills/factory-setup/reference.md` | create | Detection heuristics, precedence, edge cases |
| `plugin/skills/factory-setup/templates/config.md` | move | From `.ai-factory/config.md` (blank template), content unchanged |
| `plugin/skills/factory-design/SKILL.md` | move + modify | Template refs (lines 25, 30, 84) → read `templates/design.md` and paste it into the Architect prompt; format the Evaluator's report with `templates/evaluation.md` when persisting; config-missing → `factory-setup`; new Invoking subagents section |
| `plugin/skills/factory-design/templates/design.md` | move | From `.ai-factory/templates/design.md` |
| `plugin/skills/factory-design/templates/evaluation.md` | move | From `.ai-factory/templates/evaluation.md` |
| `plugin/skills/factory-plan/SKILL.md` | move + modify | Template refs (lines 30, 31, 77, 78) → paste `templates/epic.md` and `templates/task.md` into the Planner prompt; config check; Invoking subagents |
| `plugin/skills/factory-plan/templates/epic.md` | move | From `.ai-factory/templates/epic.md` |
| `plugin/skills/factory-plan/templates/task.md` | move | From `.ai-factory/templates/task.md` |
| `plugin/skills/factory-build/SKILL.md` | move + modify | Template refs (lines 54, 55) → skill applies `templates/review.md`/`verify.md` when persisting; precondition 3 requires Test and Lint; Step C not-configured row first with override sentence; Invoking subagents |
| `plugin/skills/factory-build/templates/review.md` | move | From `.ai-factory/templates/review.md` |
| `plugin/skills/factory-build/templates/verify.md` | move | From `.ai-factory/templates/verify.md` |
| `plugin/skills/factory-archive/SKILL.md` | move + modify | Remove `.ai-factory/templates` rules (lines 13, 30, 75) and `.ai-factory/examples` rows (What you must not touch, Edge cases) |
| `plugin/skills/factory-archive/reference.md` | move + modify | Drop the `.ai-factory/examples/oauth2/` basis and the `.ai-factory/templates/epic.md` reference |
| `plugin/evals/<case>/{prompt.md,case.yaml,fixture.sh,graders/*.md}` | create | Ten `factory-setup` eval cases listed in Testing strategy |
| `examples/oauth2/00-design.md` | move | From `.ai-factory/examples/oauth2/` |
| `examples/oauth2/evaluations/00-design-evaluation.md` | move + modify | Line 7: Design Doc path → `examples/oauth2/00-design.md` |
| `examples/oauth2/tasks/T001-add-oauth-providers.md` | move | Unchanged |
| `scripts/check.sh` | create | Structural, frontmatter, reference and Verifier contract checks (Required flags, no unconditional skip); stale-path grep excludes itself |
| `.github/workflows/check.yml` | create | Runs `check.sh`, shellcheck, `claude plugin validate .` and `claude plugin validate ./plugin` |
| `.github/workflows/sync-check.yml` | delete | Generator removed |
| `.ai-factory/sync.sh` | delete | No generator |
| `.ai-factory/framework/` (all files) | delete | Moved to `plugin/` |
| `.ai-factory/templates/` (all files) | delete | Moved into skills |
| `.ai-factory/examples/` (all files) | delete | Moved to `examples/` |
| `.claude/agents/factory-*.md` (6), `.claude/skills/factory-*/` (4 dirs) | delete | Generated adapters; contributors use `--plugin-dir ./plugin` |
| `.cursor/agents/factory-*.md` (6), `.cursor/skills/factory-*/` (4 dirs) | delete | Replaced by symlinks |
| `.cursor/agents`, `.cursor/skills` | create | Symlinks to `../plugin/agents`, `../plugin/skills` |
| `.ai-factory/projects/.gitkeep`, `.ai-factory/archive/.gitkeep` | unchanged | Already match the target layout |
| `.gitignore` | unchanged | Existing lines already match the target lines |
| `LICENSE` | create (conditional) | Only if Open Question 5 picks a license |
| `README.md` | modify | Rewrite Quick Start (Claude Code flow, Cursor user-level copy), a Team section with the `.claude/settings.json` snippet, Supported tools (namespacing, dual frontmatter), Customization (three-step ladder; the Templates subsection at line 420 now points to Eject), Project Structure, File Reference (template locations; line 460 and the `test_command`/`lint_command` text become "Test and Lint are Required and fail as not configured; a repo with no tests sets Test explicitly"), Requirements (no bash for users), Troubleshooting (update/reinstall; delete stale `~/.claude/agents/factory-*.md` carrying the "Generated by .ai-factory/sync.sh" marker, which shadow plugin agents), Contributing (`--plugin-dir`, `check.sh`, evals, acceptance run, Lint needs the `claude` CLI); remove all other `sync.sh` and `.ai-factory/framework` text (35 lines) |
| `.ai-factory/config.md` | modify | Last step, after `factory-setup` exists: becomes this repo's filled config, produced by running the skill |

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| A project `factory-<name>` agent does not replace the plugin's `soloaifactory:factory-<name>` automatically, and the `subagent_type` value for plugin agents is undocumented | medium | Explicit selection rule in every stage skill (bare-name override first, else the listed plugin name); acceptance-run check with an override present; README Troubleshooting covers stale `~/.claude/agents/factory-*.md` from `sync.sh`, which would win the bare-name rule |
| One tool might act on the other's frontmatter key (`readonly` vs `tools`) | medium | Both keys are documented per tool, and neither tool documents rejecting unknown keys; acceptance check in both tools; fallback is a 20-line render step in `check.sh`, not a return to `sync.sh` |
| Cursor has no install-from-GitHub path, so copies go stale | medium | One documented copy command, re-run to update; it deletes `factory-*` files first, so nothing removed upstream lingers |
| Agent-driven detection proposes wrong commands | medium | Mandatory confirmation with evidence; filled values never changed; apply-without-review leaves uncertain fields unfilled; unfilled Required rows fail loudly at build time instead of passing; evals for the main edge cases |
| No `version`: every commit on `main` reaches users who update | medium | Branch protection with CI; evals before merging changes to setup; `vX.Y.Z` tags allow `#ref` freezing |
| Auto-update off by default, so users run stale prompts | low | README and setup hand-off suggest turning it on; update command documented |
| Marketplace name collision (per-user registry) | low | Distinctive name `soloaifactory`; this repo never declares a second source under that name (`--plugin-dir` for dogfooding) |
| `claude plugin validate` in CI needs an install or behaves differently by version | low | Install a pinned Claude Code version in the job; `check.sh` covers JSON and paths independently |
| `claude plugin eval` is early access and costs money | low | On-demand only, with `--max-cost-usd`; manual acceptance run documented as fallback |
| An Architect or Planner invoked directly (not via a skill) has no template | low | Agent stops and points to the stage skill; README recommends skills |
| Symlinked `.cursor/` dirs fail on Windows checkouts or are not followed by Cursor | low | Contributors only; acceptance check; fallback is the user-level copy command |
| Gitignored `projects/` surprises teams that want to commit Design Docs | low | Proposal lists the lines before writing; the human can decline them, and they are not re-proposed unless the human asks to re-detect |

## Open Questions

1. **Canonical GitHub `<owner>/<repo>` for the marketplace.** The repo is still named `sdlc-orchestration-framework` while the product is soloAIfactory. Rename the repository before release? The slug appears in the add command, the README Team snippet, `plugin.json` `repository`, and the Cursor copy command.
2. **Marketplace and plugin name `soloaifactory`**: confirm. It becomes permanent in users' `enabledPlugins`; later renames need a `renames` map.
3. **Distribution reach**: submit to Cursor's public marketplace and/or Anthropic's plugin directory now, or later? Both are account actions with manual review. Proposed: later.
4. **Eval budget**: run `claude plugin eval` only manually (proposed), or also in CI with an API-key secret and a cost cap?
5. **License** for `plugin.json` and the marketplace listing (the repo has no LICENSE file today; see the conditional `LICENSE` row).

## Approval

- [x] Human has reviewed and approved this Design Doc (2026-11-19, after the revision-2 evaluation returned ready-for-planning)

<!-- Human: add comments or request revisions below -->

## Revision history

Revision 2 (2026-11-19), resolving `evaluations/00-design-evaluation.md` per human decisions:
1. "Set up" = `config.md`, Test and Lint configured, both `.gitkeep` files; optional fields and declined integrations never count; new `already-set-up` fixture.
2. Cursor project-level copy dropped; the copy removes old `factory-*` files first; Cursor overrides are project-level.
3. Apply-without-review leaves ask-branches unfilled with a reason; non-git or home directory aborts; `polyglot-no-runner` eval.
4. Templates inlined into Architect/Planner prompts; skills apply `evaluation.md`, `review.md`, `verify.md`; no `${CLAUDE_SKILL_DIR}`.
5. `check.sh` checks Required flags and the absence of an unconditional `skipped` rule.
6. `.cursor-plugin/` manifests deferred to Non-Goals.
7. Team pinning is a README snippet; setup step, risk row and evals removed.
Planner notes: self-excluding grep, anchored-regex graders, `confirmation-gate` eval, evals kept in `plugin/evals/` (required by the docs), stale-agent troubleshooting, Test Required for test-less repos, Lint needs `claude`, SHA-per-commit wording, validate `.` and `./plugin`, Impact Map fixes.

Final evaluation (revision 2, ready-for-planning). Applied: "re-detect" fills only unfilled fields and absent `.gitignore` lines; filled values are `kept` (step 4); add a `redetect-keeps-values` eval using the `partial-lint-gap` anchored-regex pattern. Binding notes for the Planner:
- **Reviewer/Verifier output floor**: when removing their template references, keep an inline list of fields each must return so the skill can fill `review.md`/`verify.md` without inventing content. Verifier: per check, command, status, exit code, output excerpt. Reviewer: per-scenario status, and findings with severity and location.
- **Subagent selection**: only `factory-design`, `factory-plan` and `factory-build` invoke subagents; `factory-archive` gets no "Invoking subagents" section.
- **README**: also fix the `.ai-factory/templates/` text at the Stage 2 and Archiving sections (current lines 177 and 210), and repoint the stage-skill links (current lines 177, 185, 199) to `plugin/skills/...`.
- **Unconditional-skip check**: match any Verifier line containing "skip" that does not also say "optional", not only the `missing from config.*skipped` wording.
- **Goal 1 count**: confirmation replies are not counted as actions.
- **Empty repo**: a failing `git log` (no commits) means "no commit history", not an error.
