# soloAIfactory

**Run a whole AI software factory as a team of one.** A line of specialized agents designs, plans, builds and inspects your software in [Cursor](https://cursor.com) and [Claude Code](https://claude.com/claude-code), with human quality gates between every stage.

You bring the requirements and make the calls at each gate. The factory turns them into a Design Doc, red-teams it, breaks it into testable work, builds each piece, and puts every piece through parallel review and verification before it reaches you. The agents and **Agent Skills** are written once, tool-neutral, in `plugin/`; `install.sh` copies them into `~/.claude/`, where both tools load them (see [Supported tools](#supported-tools)).

## How It Works

```
Path A: No Design Doc yet         Path B: Design Doc already exists

   Requirements                         Existing Design Doc
        │                                    │
        ▼                                    │
  ┌>[Architect]                              │
  │ generates/refines Design Doc             │
  │     │                                    │
  │     └──────────┬─────────────────────────┘
  │                ▼
  │           [Evaluator]  ← red teams the Design Doc
  │                │
  │                ▼
  └───────(No)── Ready for planning?
                   │
                 (Yes)
                   │
                   ▼
     Quality Gate 1: Design Doc Approval
                   │
                   ▼
               [Planner]
                   │
     creates tasks with Gherkin scenarios
                   │
                   ▼
     Quality Gate 2: Task Plan Approval
                   │
                   ▼
             Parallel Fork <─────────────────────┐
                   │                             │
      ┌────────────┼────────────┐                │
      ▼            ▼            ▼                │
   [Coder]      [Coder]      [Coder]             │
      │            │            │                │
      │   implements & tests    │                │
      │            │            │                │
      └────────────┼────────────┘                │
                   │                             │
                   ▼                             │
          Parallel Inspection Fork               │
                   │                             │
           ┌───────┴───────┐                     │
           ▼               ▼                     │
      [Reviewer]      [Verifier]                 │
     code quality     tests/lint/build           │
           │               │                     │
           └───────┬───────┘                     │
                   │                             │
                   ▼                             │
              Both pass? ──(No: Retry)───────────┘
                   │
                 (Yes)
                   │
                   ▼
     Quality Gate 3: Task Sign-off
                   │
                   ▼
                 Ship
```

## The Line: Agents as Stations

| Station       | Role                                                                    | Reads                               | Writes                                                                         | Model   | Readonly |
| ------------- | ----------------------------------------------------------------------- | ----------------------------------- | ------------------------------------------------------------------------------ | ------- | -------- |
| **Architect** | Produces the Design Doc from requirements                               | Requirements + codebase exploration | Design Doc at `.ai-factory/projects/<slug>/00-design.md`                       | inherit | no       |
| **Evaluator** | Critically evaluates Design Docs — finds flaws, blind spots, trade-offs | Design Doc + codebase exploration   | Returns critique as text (main agent persists)                                 | inherit | yes      |
| **Planner**   | Decomposes the Design Doc into self-contained Gherkin-based tasks       | Design Doc only                     | Epic at `01-epic.md` + tasks at `.ai-factory/projects/<slug>/tasks/T<id>-*.md` | inherit | no       |
| **Coder**     | Implements task + writes tests from Gherkin scenarios                   | Task file + config (+ full repo)    | Production code + tests                                                        | inherit | no       |
| **Reviewer**  | Reviews code quality, bugs, scenario coverage                           | ONE task + code diff                | Returns review report (main agent persists)                                    | inherit | yes      |
| **Verifier**  | Runs tests, lint, typecheck, build mechanically                         | Config only                         | Returns verification report (main agent persists)                              | inherit | yes      |

### Context Isolation

Like stations on a production line, each agent receives only the inputs it needs and hands off a defined output:

- **Architect** → reads requirements and codebase, writes the Design Doc
- **Evaluator** → reads the Design Doc and codebase, returns critique, never edits files
- **Planner** → reads the Design Doc only, writes self-contained tasks
- **Coder** → invoked with one task file + config (Design Doc/epic not in prompt); may read and edit anywhere in the repo per task scope
- **Reviewer** → reads ONE task + code changes, never edits code
- **Verifier** → reads config only, has no knowledge of tasks or features

The Planner is the critical translation layer. It must write tasks detailed enough that the Coder does not need the Design Doc in its prompt (the Coder may still browse the repo).

### Gherkin as the Contract

Tasks use BDD-style Gherkin scenarios that serve triple duty:

1. **Coder** — writes tests that map 1:1 to each scenario
2. **Reviewer** — checks if implementation satisfies each scenario's intent
3. **Verifier** — mechanically runs the tests the Coder wrote from those scenarios

### The Evaluator — Your Intellectual Sparring Partner

The Evaluator is not a rubber stamp. It operates under five strict rules:

1. **90% Alignment First** — If the business goals or success metrics are fuzzy, it stops and asks foundational questions before critiquing the architecture
2. **Assume Flaws** — Actively searches for bottlenecks, security vulnerabilities, scalability limits, and maintainability nightmares
3. **Evaluate Trade-offs** — Every decision has a cost. If the Design Doc doesn't mention trade-offs, the Evaluator calls them out
4. **Propose Alternatives** — For every weakness found, suggests at least one alternative approach
5. **Demand Clarity** — Calls out vagueness in data modeling, API contracts, error handling, state management, security, and observability

The Evaluator returns a structured report with: Alignment Check, Executive Summary, Critical Vulnerabilities & Blind Spots, Trade-off Analysis, Alternative Approaches, Hard Questions, and a Verdict (ready-for-planning / needs-revision / blocked).

## Quick Start

Two shell commands, then two prompts. The steps are the same in Claude Code and Cursor.

### 1. Install (once per machine)

```bash
git clone https://github.com/caicruzz/soloAIfactory.git ~/soloAIfactory
```

```bash
~/soloAIfactory/install.sh
```

Any clone location works; `~/soloAIfactory` is only an example. Run the script directly (`./install.sh` from inside the clone, or by its path as above) or with `bash install.sh`, never with `sh`: it needs bash and refuses to run under `sh`.

The installer copies the agents and skills into `~/.claude/agents/` and `~/.claude/skills/` and never writes in a repository. When it finishes, start a new Claude Code session, or restart Cursor, so the tool loads them.

### 2. Onboard a repository (once per repo)

In the target repo, say *Set up the factory in this repo* (or run `/factory-setup`). The [`factory-setup`](plugin/skills/factory-setup/SKILL.md) skill proposes, you confirm, it writes: it inspects the repo read-only, proposes every `.ai-factory/config.md` value with the evidence behind it, and writes only after you say "apply" (you can edit the proposal first). On a repo that is already set up it reports "nothing to change" and writes nothing; ask it to "re-detect" to fill only fields left unfilled. It never changes a value a human wrote.

The target repo ends up holding only `.ai-factory/config.md`, `.ai-factory/projects/.gitkeep`, `.ai-factory/archive/.gitkeep` and four `.gitignore` lines:

```gitignore
.ai-factory/projects/*
!.ai-factory/projects/.gitkeep
.ai-factory/archive/*
!.ai-factory/archive/.gitkeep
```

### 3. Start a feature

Say *Run the design stage for <feature>* to use the [`factory-design`](plugin/skills/factory-design/SKILL.md) skill, for example: *Run the design stage for OAuth2 with Google and GitHub*, or *Evaluate the Design Doc at `.ai-factory/projects/oauth2/00-design.md`*. The skill covers the Architect (when needed), the mandatory Evaluator, persisting `.ai-factory/projects/<slug>/evaluations/00-design-evaluation.md`, and the human quality gate; it documents when the subagents are invoked.

### Unattended setup

In a container or CI image, run setup without the confirmation step:

```bash
claude -p --permission-mode acceptEdits "Set up the factory in this repo. Apply the proposal without asking me."
```

The skill applies its proposal as is. Fields it is uncertain about are left unfilled rather than guessed; fill them in `.ai-factory/config.md` later (an unfilled Test or Lint makes the Verifier fail as not configured).

### Teams

Each teammate runs the same two commands on their own machine. Nothing is committed to the target repo for the install; the only shared files are the ones `factory-setup` writes, listed above.

## Updating, freezing and uninstalling

```bash
# Upgrade to the latest version
git -C ~/soloAIfactory pull && ~/soloAIfactory/install.sh

# Freeze at a release
git -C ~/soloAIfactory checkout vX.Y.Z && ~/soloAIfactory/install.sh

# Uninstall
~/soloAIfactory/install.sh --uninstall
```

None of these write in any repo. Upgrades never touch `config.md`, `projects/`, `archive/` or project overrides; they replace only the user-level `factory-*` agents and skills.

**What the installer writes.** `install.sh [--link] [--uninstall] [--force]` writes only `~/.claude/agents/factory-*.md`, `~/.claude/skills/factory-*/`, the stamp `~/.claude/.soloaifactory` and a transient `~/.claude/.soloaifactory-staging/`. It uses no network and never writes in a repo. The new set is staged first and then swapped in, so an interrupted run is repaired by re-running it.

**What it removes.** The installer removes only entries its previous stamp (`~/.claude/.soloaifactory`) lists, for example an agent that a newer version dropped. It reports any other `factory-*` entry in those two directories as left in place, and `--force` removes those too. It prints each removed path. `--uninstall` removes what the stamp lists, then the stamp.

**Exception: first install, or `--force`.** With no stamp yet (a first install), or with `--force`, the installer removes every `factory-*` entry in `~/.claude/agents/` and `~/.claude/skills/` that it does not ship, for example a hand-written `~/.claude/agents/factory-mine.md`, and replaces the entries whose names it ships. With a stamp and without `--force`, unlisted `factory-*` entries are left in place. Move any hand-written `factory-*` entry out of those directories before the first install (a project override under `.claude/agents/` is never touched).

**The stamp.** `~/.claude/.soloaifactory` records the installed commit and whether the clone had uncommitted changes (`dirty=true`), along with the source clone, the mode (`copy` or `link`), the install time and the installed agents and skills.

## Workflow

The factory runs in four stages, each ending at a human quality gate.

### Stage 1: Design

Follow [`factory-design`](plugin/skills/factory-design/SKILL.md) end-to-end.

#### Path A: Generate the Design Doc

The skill has the **Architect** explore the codebase and write `.ai-factory/projects/<slug>/00-design.md` from your feature description or requirements.

#### Path B: Bring your own Design Doc

Place your existing Design Doc at `.ai-factory/projects/<slug>/00-design.md`, then continue with the same skill (skip regeneration unless you explicitly want a refresh).

#### Both paths: Evaluate

The skill runs the **Evaluator** on `.ai-factory/projects/<slug>/00-design.md`. It critically examines the Design Doc, validates claims against the codebase, and returns a structured critique. If the verdict is `needs-revision`, the human revises the Design Doc and evaluation runs again per the skill.

**Quality gate: Review the evaluation and approve the Design Doc.**

The skill stops before Stage 2 until the human approves.

### Stage 2: Plan

Follow [`factory-plan`](plugin/skills/factory-plan/SKILL.md) after the Design Doc is human-approved. The skill uses the **Planner** to read `.ai-factory/projects/<slug>/00-design.md` and produce self-contained tasks with Gherkin scenarios under `.ai-factory/projects/<slug>/tasks/`, plus `01-epic.md` with a Mermaid task dependency graph (following the epic template bundled with the skill, [`plugin/skills/factory-plan/templates/epic.md`](plugin/skills/factory-plan/templates/epic.md)). When the plan has parallel dependency streams, the diagram **color-codes** each stream and includes a short **legend**; linear plans use a single node style.

**Quality gate: Review and approve the task plan.**

The skill requires `## Task dependency graph` in `01-epic.md` and stops at human approval before implementation; subagent invocation details live in the skill file.

### Stage 3: Build

For each task (respect dependency ordering from `01-epic.md`), follow [`factory-build`](plugin/skills/factory-build/SKILL.md), for example: *Implement T001 for `<slug>`* or *run the build loop for the next task*.

The skill defines the loop: **Coder** implements from the task file and Gherkin; **Reviewer** and **Verifier** run **in parallel**; failures get **appended** feedback and another Coder pass; when both pass, results go to the human. Reviewer uses the task path; Verifier uses the task ID and `.ai-factory/config.md` only. Every scenario must map to tests; ordering follows the epic DAG.

**Quality gate: Approve the completed task.**

For low-level or custom orchestration you can invoke the `factory-coder`, `factory-reviewer`, and `factory-verifier` subagents directly (see [Supported tools](#supported-tools)); prefer driving work through `factory-build` so gates and parallelism stay consistent.

### Stage 4: Ship

After all tasks pass review and verification, the feature is ready for final human review and merge.

### Archiving a project

When a feature has shipped, use the [`factory-archive`](plugin/skills/factory-archive/SKILL.md) skill; more detail in [`reference.md`](plugin/skills/factory-archive/reference.md).

**How to use it.** In Cursor or Claude Code, ask the agent in plain language, for example: *Archive project `my-feature`*, *archive `oauth2`*, or *clean up the factory project for that slug*. The agent follows the skill: it confirms the slug, that the **Design Doc will move** into the archive, and that the `projects/<slug>` tree will be removed.

**What you get.** One self-contained run folder, **no duplicate `project-summary`**, and the slug directory under `projects/` is removed (you can start a new feature with the same slug later if needed).

| Location                                | After a successful archive                                                                                                                                                                                                                   |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.ai-factory/archive/<slug>/<timestamp>/` | `00-design.md` — moved from `projects/` (not edited), `project-summary.md` — single summary (epic, evaluation highlights, one section per task with review/verify), `dependency-graph.md` — full Mermaid + legend from `01-epic` when available |
| `.ai-factory/projects/<slug>/`            | **Removed** (empty after the move and cleanup)                                                                                                                                                                                               |

**What stays** elsewhere: all of `.ai-factory/` except that slug (config and other slugs' folders).

**Git.** `factory-setup` proposes the four `.gitignore` lines (you can decline them); once applied, `.ai-factory/projects/*` and `.ai-factory/archive/*` are **gitignored** (with `.gitkeep` placeholders) and local factory and archive output stay off the default commit unless you opt in.

## Project Structure

This repository holds the factory's sources, the installer and its tests. It has no `.claude/` or `.cursor/` directory: nothing here is loaded from the repo itself; `install.sh` copies `plugin/` into `~/.claude/`.

```
install.sh                         # Installs plugin/ into ~/.claude/ (--link, --uninstall, --force)
plugin/
  .claude-plugin/plugin.json       # Plugin manifest
  agents/                          # The six subagents (installed to ~/.claude/agents/)
    factory-architect.md
    factory-evaluator.md           # Design Doc red team
    factory-planner.md
    factory-coder.md
    factory-reviewer.md
    factory-verifier.md
  skills/                          # One skill per stage (installed to ~/.claude/skills/)
    factory-setup/                 # Onboard a repo: propose and write .ai-factory/config.md
      SKILL.md
      reference.md                 # Detection heuristics
      templates/config.md
    factory-design/                # Stage 1: Design Doc paths + Evaluator + quality gate
      SKILL.md
      templates/design.md          # Design Doc template
      templates/evaluation.md      # Evaluator report template
    factory-plan/                  # Stage 2: Planner, epic + task DAG, quality gate
      SKILL.md
      templates/epic.md            # Epic + Mermaid dependency graph
      templates/task.md
    factory-build/                 # Stage 3: Coder, parallel review/verify, per-task loop
      SKILL.md
      templates/review.md
      templates/verify.md
    factory-archive/               # Clean up a finished .ai-factory/projects slug
      SKILL.md
      reference.md
  evals/                           # factory-setup eval cases (never installed)
examples/
  oauth2/                          # Example artifacts for reference
    00-design.md
    evaluations/
      00-design-evaluation.md      # Example evaluation
    tasks/
      T001-add-oauth-providers.md
scripts/
  test.sh                          # Runs check.sh and every scripts/test-*.sh
  lint.sh                          # bash -n + shellcheck on every *.sh
  check.sh                         # Repository consistency checks
  test-*.sh                        # One test script per area (test-install.sh, test-readme.sh, ...)
  run-evals.sh                     # Paid factory-setup evals (needs ANTHROPIC_API_KEY)
.github/
  workflows/check.yml              # CI: test.sh on Ubuntu and macOS, lint.sh on Ubuntu
.ai-factory/                       # This repo's own factory state
  config.md                        # Project configuration (written by factory-setup)
  projects/                        # Work in progress (gitignored, with .gitkeep)
    <slug>/
      00-design.md
      evaluations/
        00-design-evaluation.md    # Evaluator report (persisted by main agent)
      01-epic.md
      tasks/
        T001-<slug>.md
      reviews/
        T001-review.md             # Reviewer report (persisted by main agent)
      verifications/
        T001-verify.md             # Verifier report (persisted by main agent)
  archive/                         # Self-contained archive runs (gitignored, with .gitkeep)
    <slug>/
      <timestamp>/
        00-design.md               # Moved from projects/<slug>/
        dependency-graph.md        # Mermaid + legend (from 01-epic)
        project-summary.md         # Single summary; links to ./00-design and ./dependency-graph
```

## Important Implementation Details

### Two Entry Paths

The factory supports two starting points:

**Path A** — No Design Doc exists. The Architect generates one from requirements, then the Evaluator critiques it. This is the full agent-driven path.

**Path B** — A Design Doc already exists (written by a human, by another tool, or from a previous session). Skip directly to the Evaluator.

Both paths converge at the Evaluator. No Design Doc reaches the Planner without being stress-tested. This prevents garbage-in-garbage-out — whether the Design Doc came from the Architect, a human, or ChatGPT, it gets the same adversarial review.

### Task Status Lifecycle

```
draft → in-progress → implemented → done
  │                       │    ↑
  └──→ blocked            │    │
                          │    │
                     review/verify failed
                     → feedback appended
                     → Coder re-invoked
                     → back to implemented
```

- `draft` — Task created by Planner, awaiting implementation
- `in-progress` — Coder is actively working on it
- `implemented` — Coder finished, awaiting review + verification
- `done` — Passed review + verification + human approval
- `blocked` — Coder found a contradiction or impossible scenario

### The Coder-Reviewer-Verifier Loop

The core quality enforcement mechanism is the parallel fork-join loop, the factory's inspection station:

```
Coder implements
      │
  ┌───┴───┐          ← fork: both run in parallel
  ▼       ▼
Reviewer  Verifier    ← different concerns, different models
  │       │
  └───┬───┘          ← join: both must pass
      │
  both pass ──▶ Human sign-off ──▶ Done
  any fail  ──▶ feedback to Coder ──▶ loop
```

**Reviewer** checks the *semantic* quality:

- Does the code actually satisfy each Gherkin scenario?
- Are there bugs, edge cases, performance issues?
- Is the code following project conventions?

**Verifier** checks the *mechanical* quality:

- Do all tests pass?
- Is the linting clean?
- Does the type checker pass?
- Does the build succeed?

If the Reviewer passes but the Verifier fails, the implementation approach is sound but something is mechanically broken. If the Verifier passes but the Reviewer finds issues, the tests are passing but the coverage is incomplete or the code quality is insufficient. Both must agree.

### Coder Autonomy

The Coder has autonomy in two key areas:

1. **How to implement** — The Coder decides the implementation approach as long as it satisfies the Gherkin scenarios
2. **Whether to address Reviewer feedback** — The Coder is not required to implement every Reviewer suggestion. It must only ensure all Gherkin scenarios are satisfied. Low-severity style preferences can be declined with reasoning

This is by design. The Planner's Gherkin scenarios are the contract. Everything else is advisory.

### Human Quality Gates

Four mandatory human checkpoints in every run:

1. **Design Doc Evaluation** — Review the Evaluator's critique and decide whether the Design Doc is ready for planning
2. **Task Plan Approval** — Review the task decomposition for scope and ordering
3. **Task Sign-off** — Review the review report + verification results before marking done
4. **Final Merge** — Review the complete feature before merging

Use the `factory-design`, `factory-plan`, and `factory-build` skills so the orchestrator follows the stages, parallel review/verify, and these gates explicitly — skills replace a separate always-on workflow rule.

## Supported tools

soloAIfactory targets **Cursor** and **Claude Code** with one install. `install.sh` writes only to `~/.claude/agents/` and `~/.claude/skills/`, which Claude Code reads natively and Cursor reads for compatibility. Prompts, skills and templates are the same files for both tools.

| | Cursor | Claude Code |
|---|---|---|
| Agents | `~/.claude/agents/factory-*.md` | `~/.claude/agents/factory-*.md` |
| Skills | `~/.claude/skills/factory-*/` | `~/.claude/skills/factory-*/` |
| Invoking a subagent | Delegate by name, e.g. `/factory-coder <task path>` | Agent tool with `subagent_type: factory-coder` |
| Read-only agents | `readonly: true` frontmatter | `tools:` allowlist (no Edit or Write) |

### Agent frontmatter

Read-only agents carry both keys, one per tool:

```yaml
---
name: factory-reviewer
description: What the agent does and when to use it.
model: inherit
readonly: true                  # read by Cursor
tools: Read, Grep, Glob, Bash   # read by Claude Code
---
```

Each tool ignores the other's key. Writable agents (Architect, Planner, Coder) carry neither.

Read-only agents (Evaluator, Reviewer, Verifier) never write files: they return their report and the orchestrating skill persists it. In Claude Code the `tools:` allowlist leaves out Edit and Write for all three, and the Evaluator (`tools: Read, Grep, Glob`) has no shell at all, so it is hard read-only. The Reviewer (`git diff`) and Verifier (test/lint/build commands) need `Bash`, which can still write files, so for them read-only also relies on the prompt.

## Customizing for Your Project

Three steps, cheapest first. Use the first one that does the job.

### 1. Project rules in `config.md`

Add project rules to `.ai-factory/config.md` under **Conventions** and **Architecture Notes** (for example "always use the repository pattern" or "every public endpoint needs an integration test"). Every agent reads `config.md`, it is committed with the repo, so the whole team shares it, and upgrades never touch it. The Verifier reads the **Commands** table from the same file.

### 2. Override one agent in one project

Commit `.claude/agents/factory-<name>.md` with `name: factory-<name>` in its frontmatter to the target repo. Both tools read it, and a project agent takes precedence over the installed user-level agent of the same name. (`.cursor/agents/factory-<name>.md` also works, for Cursor only.) Start from a copy of `plugin/agents/factory-<name>.md`. Never edit `~/.claude/agents/factory-*`: the next install replaces it.

**Cost.** An override does not receive upgrades: when the factory's agent changes, your copy stays as it was until you merge the change by hand.

**Contracts an override must keep**, because the skills depend on them:

- The **Architect** and **Planner** follow the template the skill pastes into their prompt, and stop without writing anything when there is none.
- The **Reviewer** returns a status per scenario and findings with severity and location.
- The **Verifier** reads the **Commands** labels, reports an unconfigured Required check as `fail` (not configured), and returns per check the command, status, exit code and an output excerpt.
- Read-only agents carry both `readonly: true` and `tools:`.

Overriding the Coder, Architect or Planner is supported. Overriding the Reviewer or Verifier is unsupported: the build loop's gate reads their reports. `factory-build` names any project override it uses at the start of a loop (`using project override <path>`).

### 3. Change skills or templates: fork and install

To change a skill, a template or an agent for every repo, fork this repository, edit `plugin/`, and run `install.sh` from your fork. A project copy of a skill does not work in Claude Code, where a personal skill beats a project skill, so the installed user-level copy is the one to change.

#### Templates

Templates are bundled with the skill that uses them, under `plugin/skills/<skill>/templates/`, and define the output format. To change them, fork and install (step 3), for example to:

- Add sections specific to your domain (e.g., compliance, accessibility)
- Change the review severity levels
- Add required fields to the Design Doc
- Adjust the Evaluator's output structure

#### Adding new agents or skills

In your fork, add `plugin/agents/factory-<name>.md` (frontmatter as in [Agent frontmatter](#agent-frontmatter)) or `plugin/skills/factory-<name>/SKILL.md` (the frontmatter `name` must match the folder name), then run `install.sh`. The installer picks up only `factory-*` names. Each tool delegates based on the description.

## File Reference

### `plugin/skills/factory-plan/templates/task.md` — The Most Critical File

The task template is the linchpin of the factory. A well-written task:

- States a one-sentence business **Objective**
- Uses **Acceptance Criteria** (Gherkin scenarios) as the primary spec — mappable directly to tests
- Keeps technical detail in optional **Dev Notes** (paths, snippets, constraints, dependency interfaces)
- Lists dependencies briefly without front-loading implementation detail

The [`examples/oauth2/tasks/T001-add-oauth-providers.md`](examples/oauth2/tasks/T001-add-oauth-providers.md) file demonstrates a fully populated task.

### `plugin/skills/factory-design/templates/design.md` — The Design Doc

The Architect fills this template to produce `00-design.md`: metadata, problem statement, goals and non-goals, architecture overview, data model and API surface changes, a file impact map, risks and mitigations, open questions, and an approval checklist. Bring-your-own Design Docs should follow the same structure. [`examples/oauth2/00-design.md`](examples/oauth2/00-design.md) is an example.

### `plugin/skills/factory-plan/templates/epic.md` — Epic and Mermaid dependency graph

The Planner uses this for `01-epic.md`: task list, a fenced Mermaid diagram of the full DAG (edge direction: prerequisite → dependent), optional `classDef` colors per parallel stream with a neutral style for merge tasks, and a legend.

### `plugin/skills/factory-design/templates/evaluation.md` — The Evaluator's Output Format

The evaluation template structures the Evaluator's critique into: Alignment Check, Executive Summary, Critical Vulnerabilities & Blind Spots, Trade-off Analysis, Alternative Approaches, Hard Questions, and a Verdict.

The [`examples/oauth2/evaluations/00-design-evaluation.md`](examples/oauth2/evaluations/00-design-evaluation.md) file demonstrates a full evaluation showing how the Evaluator critiques a real Design Doc.

### `.ai-factory/config.md` — Project Configuration

Created in each target repo by `factory-setup`. Every agent reads it; the Verifier reads its **Commands** table. The Commands labels (Install, Test, Lint, Type check, Build, Format) are frozen: agents find rows by these exact labels, so do not rename them. Test and Lint are Required and fail as not configured; a repo with no tests sets Test explicitly. Type check and Build are optional and skipped when unset or `none`.

### `plugin/skills/` — Workflow (stages and gates)

The factory's procedure (onboarding, paths, Evaluator, Planner, build loop, human quality gates) lives in the `factory-setup`, `factory-design`, `factory-plan`, `factory-build`, and `factory-archive` skills. Invoke or follow those skills instead of a separate always-on workflow rule.

## Requirements

- [Cursor](https://cursor.com) with agent mode, and/or [Claude Code](https://claude.com/claude-code)
- git and bash 3.2+ (macOS `/bin/bash` works)
- Windows: run `install.sh` from Git Bash when Claude Code and Cursor run natively (copy mode only; `--link` is not supported there), and from WSL only when the tools themselves run inside WSL
- A project with a test runner and a linter (Test and Lint are Required checks)
- No other dependencies — this is pure configuration

## Troubleshooting

- **Skills or agents not showing.** Start a new Claude Code session or restart Cursor; tools load `~/.claude/` at startup.
- **An old copy takes priority.** Old `~/.cursor/agents/factory-*` and `~/.cursor/skills/factory-*` copies, and old project adapters under `.claude/` or `.cursor/` from the retired generator, take priority over the install. Delete them. The project adapters carry this marker:

  ```
  Generated by .ai-factory/sync.sh
  ```

  `install.sh` warns about the `~/.cursor` copies and `factory-setup` warns about marked project adapters, but neither ever deletes them.
- **`CLAUDE_CONFIG_DIR` is set.** Claude Code reads that directory instead of `~/.claude`, so it will not see the install; Cursor will. `install.sh` warns when this applies.
- **`~/.claude/skills` (or `~/.claude/agents`) is a symlink.** The files land in its target; `install.sh` warns and names the target.
- **Which version is installed?** Read `~/.claude/.soloaifactory`: it records the installed commit and whether the clone had uncommitted changes.

## Contributing

1. Run `./install.sh --link` once. The user-level entries become symlinks into your working tree, so edits under `plugin/` apply in every repo, this one included; the checked-out branch is what runs everywhere.
2. Run `scripts/test.sh` and `scripts/lint.sh` before every push. CI runs `test.sh` on Ubuntu and on macOS `/bin/bash`, and `lint.sh` on Ubuntu.
3. Add or extend a `scripts/test-*.sh` file for every change; `scripts/test.sh` picks it up automatically.
4. Before merging changes to `factory-setup`, run `scripts/run-evals.sh --max-cost-usd <usd>`. It makes paid model calls and needs `ANTHROPIC_API_KEY`.

### Manual acceptance run

Some behaviour depends on the tools themselves and is checked by hand before a release.

**Preconditions.** `./install.sh` prints no `~/.cursor/{agents,skills}/factory-*` warning, and the fixtures contain no generated adapters. Start with no `~/.claude/agents` or `~/.claude/skills`.

**Checks.**

1. First run: install, then in a fixture repo run setup and `factory-design` Path A, and confirm the Architect is found. Do this after a new Claude Code session and after a Cursor restart; then repeat with `/reload-skills` (Claude Code) and **Developer: Reload Window** (Cursor) instead.
2. Setup on two eval fixtures (from `plugin/evals/`): a re-run reports already set up, and `git status` is clean.
3. `factory-design` produces a Design Doc that follows the `design.md` template's headings.
4. In Cursor, each agent and skill is listed once.
5. `readonly` (Cursor) and `tools:` (Claude Code) are honoured per tool.
6. A committed `.claude/agents/factory-coder.md` override is named and used by `factory-build`.
7. A planted generated adapter is warned about and not deleted.
8. With `--link`, an edit under `plugin/` takes effect in both tools.

## Acknowledgments

Built on [Agent Skills](https://cursor.com/docs/skills) and subagents in [Cursor](https://cursor.com/docs/subagents) and [Claude Code](https://docs.claude.com/en/docs/claude-code/sub-agents), using the orchestrator pattern with context isolation.
