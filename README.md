# Agent Orchestration Framework

An agent-driven SDLC framework for [Cursor](https://cursor.com). Define features, decompose them into testable tasks, implement with autonomous agents, and enforce quality through parallel review and verification — all controlled by human gates. **Agent Skills** in `**.cursor/skills/`** are a first-class part of the stack: they package workflows (phases, gates, agent order), conventions, and tooling alongside the [agents](#agents) and `**.sdlc/**` config.

## How It Works

```
Path A: No TDD exists             Path B: TDD already exists

Requirements                      Existing TDD
     │                                 │
     ▼                                 │
 [Architect]                            │
  generates TDD                         │
     │                                  │
     └──────────────┬───────────────────┘
                    ▼
            [Evaluator]  ← red teams the TDD
                    │
                    ▼
            Human gate: review evaluation
                    │
                    ▼
                   [Planner]
                         │
                   creates self-contained tasks with Gherkin scenarios
                         │
              ┌──────────┼──────────┐
              ▼          ▼          ▼
          [Coder]    [Coder]    [Coder]     ← each invoked with ONE task (+ config); full repo for implementation
              │          │          │
          implements + writes tests from Gherkin
              │          │          │
              └──────────┼──────────┘
                         │
                    ┌────┴────┐  ← parallel fork
                    ▼         ▼
             [Reviewer]  [Verifier]
             code quality  tests/lint/build
                    │         │
                 both pass?───┘
                    │
               ┌────┴────┐
            No ─┤         ├── Yes
               back to    Human sign-off
               Coder           │
                            Done
```

## Agents


| Agent         | Role                                                             | Reads                               | Writes                                                                   | Model   | Readonly |
| ------------- | ---------------------------------------------------------------- | ----------------------------------- | ------------------------------------------------------------------------ | ------- | -------- |
| **Architect** | Produces Technical Design Document from requirements             | Requirements + codebase exploration | TDD at `.sdlc/projects/<slug>/00-tdd.md`                                 | inherit | no       |
| **Evaluator** | Critically evaluates TDDs — finds flaws, blind spots, trade-offs | TDD + codebase exploration          | Returns critique as text (main agent persists)                           | inherit | yes      |
| **Planner**   | Decomposes TDD into self-contained Gherkin-based tasks           | TDD only                            | Epic at `01-epic.md` + tasks at `.sdlc/projects/<slug>/tasks/T<id>-*.md` | inherit | no       |
| **Coder**     | Implements task + writes tests from Gherkin scenarios            | Task file + config (+ full repo)    | Production code + tests                                                  | inherit | no       |
| **Reviewer**  | Reviews code quality, bugs, scenario coverage                    | ONE task + code diff                | Review report                                                            | inherit | yes      |
| **Verifier**  | Runs tests, lint, typecheck, build mechanically                  | Config only                         | Verification report                                                      | fast    | yes      |


### Context Isolation

Each agent operates with strict context boundaries:

- **Architect** → reads requirements and codebase, writes TDD
- **Evaluator** → reads TDD and codebase, returns critique, never edits files
- **Planner** → reads TDD only, writes self-contained tasks
- **Coder** → invoked with one task file + config (TDD/epic not in prompt); may read and edit anywhere in the repo per task scope
- **Reviewer** → reads ONE task + code changes, never edits code
- **Verifier** → reads config only, has no knowledge of tasks or features

The Planner is the critical translation layer. It must write tasks detailed enough that the Coder does not need the TDD in its prompt (the Coder may still browse the repo).

### Gherkin as the Contract

Tasks use BDD-style Gherkin scenarios that serve triple duty:

1. **Coder** — writes tests that map 1:1 to each scenario
2. **Reviewer** — checks if implementation satisfies each scenario's intent
3. **Verifier** — mechanically runs the tests the Coder wrote from those scenarios

### The Evaluator — Your Intellectual Sparring Partner

The Evaluator is not a rubber stamp. It operates under five strict rules:

1. **90% Alignment First** — If the business goals or success metrics are fuzzy, it stops and asks foundational questions before critiquing the architecture
2. **Assume Flaws** — Actively searches for bottlenecks, security vulnerabilities, scalability limits, and maintainability nightmares
3. **Evaluate Trade-offs** — Every decision has a cost. If the TDD doesn't mention trade-offs, the Evaluator calls them out
4. **Propose Alternatives** — For every weakness found, suggests at least one alternative approach
5. **Demand Clarity** — Calls out vagueness in data modeling, API contracts, error handling, state management, security, and observability

The Evaluator returns a structured report with: Alignment Check, Executive Summary, Critical Vulnerabilities & Blind Spots, Trade-off Analysis, Alternative Approaches, Hard Questions, and a Verdict (ready-for-planning / needs-revision / blocked).

## Quick Start

### 1. Copy into your project

```bash
cp -r .cursor/ /path/to/your/project/.cursor/
cp -r .sdlc/ /path/to/your/project/.sdlc/
```

That copies **agents** and **skills** — the full `[.cursor/skills/](#cursor-skills)` tree is part of the framework; keep it in sync with this repository.

### 2. Configure your project

Edit `.sdlc/config.md` to match your tech stack:

```markdown
## Tech Stack
- **Language**: TypeScript
- **Runtime**: Node.js 22
- **Framework**: Express
- **Package Manager**: npm

## Commands
| Check | Command |
|---|---|
| **Test** | npm test |
| **Lint** | npm run lint |
| **Type check** | npx tsc --noEmit |
| **Build** | npm run build |
```

### 3. Start a feature

Use the **[`sdlc-tdd`](.cursor/skills/sdlc-tdd/SKILL.md)** skill in natural language—for example: *Run Phase 1 SDLC for OAuth2 with Google and GitHub*, or *Evaluate the TDD at `.sdlc/projects/oauth2/00-tdd.md`*. The skill covers Architect (when needed), mandatory Evaluator, persisting **`.sdlc/projects/<slug>/evaluations/00-tdd-evaluation.md`**, and the human approval gate; it documents when **`.cursor/agents/`** subagents are invoked.

## Workflow

### Phase 1: Design

Follow **[`sdlc-tdd`](.cursor/skills/sdlc-tdd/SKILL.md)** end-to-end.

#### Path A: Generate TDD

The skill has the **Architect** explore the codebase and write **`.sdlc/projects/<slug>/00-tdd.md`** from your feature description or requirements.

#### Path B: Bring your own TDD

Place your existing TDD at **`.sdlc/projects/<slug>/00-tdd.md`**, then continue with the same skill (skip regeneration unless you explicitly want a refresh).

#### Both paths: Evaluate

The skill runs the **Evaluator** on **`.sdlc/projects/<slug>/00-tdd.md`**. It critically examines the TDD, validates claims against the codebase, and returns a structured critique. If the verdict is `needs-revision`, the human revises the TDD and evaluation runs again per the skill.

**Human gate: Review the evaluation and approve the TDD.**

The skill stops before Phase 2 until the human approves.

### Phase 2: Planning

Follow **[`sdlc-plan`](.cursor/skills/sdlc-plan/SKILL.md)** after the TDD is human-approved. The skill uses the **Planner** to read **`.sdlc/projects/<slug>/00-tdd.md`** and produce self-contained tasks with Gherkin scenarios under **`.sdlc/projects/<slug>/tasks/`**, plus **`01-epic.md`** with a **Mermaid task dependency graph** (following **`.sdlc/templates/epic.md`**). When the plan has parallel dependency streams, the diagram **color-codes** each stream and includes a short **legend**; linear plans use a single node style.

**Human gate: Review and approve the task plan.**

The skill requires **`## Task dependency graph`** in **`01-epic.md`** and stops at human approval before implementation; subagent invocation details live in the skill file.

### Phase 3: Implementation Loop

For each task (respect dependency ordering from **`01-epic.md`**), follow **[`sdlc-implement`](.cursor/skills/sdlc-implement/SKILL.md)**—for example: *Implement T001 for `<slug>`* or *run the SDLC implement loop for the next task*.

The skill defines the loop: **Coder** implements from the task file and Gherkin; **Reviewer** and **Verifier** run **in parallel**; failures get **appended** feedback and another Coder pass; when both pass, results go to the human. Reviewer uses the task path; Verifier uses the task ID and **`.sdlc/config.md`** only. Every scenario must map to tests; ordering follows the epic DAG.

**Human gate: Approve the completed task.**

For low-level or custom orchestration, the **`.cursor/agents/`** definitions still document explicit subagent calls (e.g. **`/sdlc-coder`**, **`/sdlc-reviewer`**, **`/sdlc-verifier`**); prefer driving work through **`sdlc-implement`** so gates and parallelism stay consistent.

### Phase 4: Completion

After all tasks pass review and verification, the feature is ready for final human review and merge.

### Archiving a project

When a feature is finished, use the **SDLC archive** skill in [`.cursor/skills/sdlc-archive/SKILL.md`](.cursor/skills/sdlc-archive/SKILL.md). It ships with a full [`.cursor/`](.cursor/) copy (see [Quick Start](#1-copy-into-your-project)); more detail in [`.cursor/skills/sdlc-archive/reference.md`](.cursor/skills/sdlc-archive/reference.md). To add or update skills without recopying everything, follow [Cursor skills](#cursor-skills).

**How to use it.** In Cursor, ask the agent in plain language, for example: *Archive SDLC project `my-feature`*, *archive project `oauth2`*, or *clean up the .sdlc project for that slug*. The agent follows the skill: confirm the slug, that the **TDD will move** into the archive, and that the **`projects/<slug>`** tree will be removed.

**What you get.** One self-contained run folder, **no duplicate `project-summary`**, and the slug directory under `projects/` is removed (you can start a new feature with the same slug later if needed).

| Location | After a successful archive |
|----------|----------------------------|
| **`.sdlc/archive/<slug>/<timestamp>/`** | **`00-tdd.md`** — moved from `projects/` (not edited), **`project-summary.md`** — single summary (epic, evaluation highlights, one section per task with review/verify), **`dependency-graph.md`** — full Mermaid + legend from `01-epic` when available |
| **`.sdlc/projects/<slug>/`** | **Removed** (empty after the move and cleanup) |

**What stays** elsewhere: all of **`.sdlc/`** except that slug (config, templates, other slugs’ folders). The framework’s **`.sdlc/templates/`** is never deleted.

**Git.** In this repository, **`.sdlc/projects/*`** and **`.sdlc/archive/*`** are **gitignored** (with `.gitkeep` placeholders) so local SDLC and archive output stay off the default commit unless you opt in.

## Project Structure

```
.cursor/
  agents/                          # Agent definitions
    sdlc-architect.md
    sdlc-evaluator.md              # TDD red team
    sdlc-planner.md
    sdlc-coder.md
    sdlc-reviewer.md
    sdlc-verifier.md
  skills/                          # Core: packaged workflows + SDLC phases (see Cursor skills)
    sdlc-tdd/                      # Phase 1: TDD paths + Evaluator + approval gate
      SKILL.md
    sdlc-plan/                     # Phase 2: Planner, epic + task DAG, approval gate
      SKILL.md
    sdlc-implement/                # Phase 3: Coder, parallel review/verify, per-task loop
      SKILL.md
    sdlc-archive/                  # e.g. clean up a finished .sdlc/projects slug
      SKILL.md
      reference.md
.sdlc/
  config.md                        # Project-specific configuration
  templates/                       # Output format templates
    tdd.md
    evaluation.md                  # Evaluator report template
    epic.md                        # Epic + Mermaid dependency graph
    task.md
    review.md
    verify.md
  projects/                        # Generated artifacts (gitignored)
    <slug>/
      00-tdd.md
      evaluations/
        00-tdd-evaluation.md       # Evaluator report (persisted by main agent)
      01-epic.md
      tasks/
        T001-<slug>.md
      reviews/
        T001-review.md
      verifications/
        T001-verify.md
  archive/                         # Self-contained SDLC archive runs (gitignored)
    <slug>/
      <timestamp>/
        00-tdd.md                  # Moved from projects/<slug>/
        dependency-graph.md        # Mermaid + legend (from 01-epic)
        project-summary.md         # Single summary; links to ./00-tdd and ./dependency-graph
  examples/                        # Example artifacts for reference
    oauth2/
      00-tdd.md
      evaluations/
        00-tdd-evaluation.md       # Example evaluation
      tasks/
        T001-add-oauth-providers.md
```

## Important Implementation Details

### Two Entry Paths

The framework supports two starting points:

**Path A** — No TDD exists. The Architect generates one from requirements, then the Evaluator critiques it. This is the full agent-driven path.

**Path B** — A TDD already exists (written by a human, by another tool, or from a previous session). Skip directly to the Evaluator.

Both paths converge at the Evaluator. No TDD reaches the Planner without being stress-tested. This prevents garbage-in-garbage-out — whether the TDD came from the Architect, a human, or ChatGPT, it gets the same adversarial review.

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

The core quality enforcement mechanism is the parallel fork-join loop:

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

### Human Gates

Four mandatory human checkpoints in every workflow:

1. **TDD Evaluation** — Review the Evaluator's critique and decide whether the TDD is ready for planning
2. **Task Plan Approval** — Review the task decomposition for scope and ordering
3. **Task Sign-off** — Review the review report + verification results before marking done
4. **Final Merge** — Review the complete feature before merging

Use the **[`sdlc-tdd`](#cursor-skills)**, **`sdlc-plan`**, and **`sdlc-implement`** skills so the orchestrator follows phases, parallel review/verify, and these gates explicitly—skills replace a separate always-on workflow rule.

## Installation Scopes

Cursor supports two scopes for agents and skills: **project-level** and **user-level**.

### Project-Level (per repo)

This is what the Quick Start section covers. Agents and config live inside the project:

```
your-project/
  .cursor/
    agents/           ← project-scoped agents
    skills/           ← core: one subfolder per skill (see Cursor skills)
  .sdlc/
    config.md         ← project-specific config
    templates/        ← project-specific templates
```

Use this when:

- The project has specific conventions, test frameworks, or architecture patterns
- You want the framework checked into version control for the whole team
- Templates need to be customized for the project's domain

### Cursor skills

**Skills are core to this framework** — not an add-on. They ship how-to for workflows (Phase 1 [`sdlc-tdd`](.cursor/skills/sdlc-tdd/SKILL.md), Phase 2 [`sdlc-plan`](.cursor/skills/sdlc-plan/SKILL.md), Phase 3 [`sdlc-implement`](.cursor/skills/sdlc-implement/SKILL.md), project archive, and more), keep conventions consistent, and will grow as we add more capabilities. Cursor loads [Agent Skills](https://cursor.com/docs/context/skills) from `**.cursor/skills/<skill-name>/`** in the workspace, and from `**~/.cursor/skills/<skill-name>/**` when you install them globally. Each skill lives in its **own subfolder** so the entry file can stay named `SKILL.md` without colliding.

**Layout (identify the skill by folder name, not by filename):**

```
.cursor/skills/
  sdlc-tdd/           # Phase 1: TDD + Evaluator + human approval gate
    SKILL.md
  sdlc-plan/          # Phase 2: Planner + epic + task DAG + human approval gate
    SKILL.md
  sdlc-implement/     # Phase 3: Coder + parallel review/verify + human approval per task
    SKILL.md
  sdlc-archive/
    SKILL.md          ← instructions (name in frontmatter is sdlc-archive)
    reference.md      ← supplementary note (if present)
  <other-skill>/
    SKILL.md
```

The `**name**` field in each `SKILL.md` should match the parent folder name (see the [skills](https://cursor.com/docs/context/skills) docs).

**Do not** copy loose `SKILL.md` files into `**.cursor/skills/`** — every skill uses the same filename, so they would overwrite each other and you could not tell which skill is which without opening the file. **Always copy the whole named directory** (or the whole `skills/` tree).


| Goal                                              | Command (adjust paths)                                                                                                                    |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| **All skills** from this framework into a project | `mkdir -p your-project/.cursor && cp -r /path/to/orchestration-framework/.cursor/skills your-project/.cursor/`                            |
| **One skill** (e.g. SDLC archive) into a project  | `mkdir -p your-project/.cursor/skills && cp -r /path/to/orchestration-framework/.cursor/skills/sdlc-archive your-project/.cursor/skills/` |
| **Phase 1 skill only** (TDD + Evaluator)          | `mkdir -p your-project/.cursor/skills && cp -r /path/to/orchestration-framework/.cursor/skills/sdlc-tdd your-project/.cursor/skills/`       |
| **Phase 2 skill only** (Planner + epic + tasks)   | `mkdir -p your-project/.cursor/skills && cp -r /path/to/orchestration-framework/.cursor/skills/sdlc-plan your-project/.cursor/skills/`        |
| **Phase 3 skill only** (implement + CR loop)       | `mkdir -p your-project/.cursor/skills && cp -r /path/to/orchestration-framework/.cursor/skills/sdlc-implement your-project/.cursor/skills/`  |
| **All skills** globally (every repo)              | `mkdir -p ~/.cursor/skills && cp -r /path/to/orchestration-framework/.cursor/skills/* ~/.cursor/skills/`                                  |
| **One skill** globally                            | `mkdir -p ~/.cursor/skills && cp -r /path/to/orchestration-framework/.cursor/skills/sdlc-archive ~/.cursor/skills/`                       |


If `**~/.cursor/skills/`** already contains other skills, copying a **single** named folder only adds or replaces that folder; using `cp -r .../skills/`* merges the full set (still one subfolder per skill).

### User-Level (global, all projects)

Agents and skills can also be installed globally so they're available in **every** project without copying files:

```
~/.cursor/
  agents/              ← user-scoped agents (all projects)
    sdlc-architect.md
    sdlc-evaluator.md
    sdlc-planner.md
    sdlc-coder.md
    sdlc-reviewer.md
    sdlc-verifier.md
  skills/              ← user-scoped skills (same layout as .cursor/skills/)
    <skill-name>/
      SKILL.md
```

Cursor also reads from Claude and Codex compatibility paths:

- `~/.claude/agents/`
- `~/.codex/agents/`

Use this when:

- You want the SDLC agents available in every repo without setup
- You work across many projects and don't want to copy agents each time
- You have personal preferences for agent behavior that apply everywhere

#### Setting up global agents

```bash
# Copy agents to your user-level config
cp .cursor/agents/*.md ~/.cursor/agents/

# Or link them to keep in sync with this repo
ln -s $(pwd)/.cursor/agents/*.md ~/.cursor/agents/
```

#### Global agents + project config

The most effective setup combines both scopes:


| Scope                                | What to install                | Why                                                  |
| ------------------------------------ | ------------------------------ | ---------------------------------------------------- |
| **User-level** (`~/.cursor/agents/`) | All 6 agents                   | Available everywhere, no per-project copy            |
| **User-level** (`~/.cursor/skills/`) | All skills from this framework | SDLC phases, gates, and procedures in every repo     |
| **Project-level** (`.sdlc/`)         | `config.md` + templates        | Project-specific stack, commands, and output formats |


Agents and skills are global when installed under `~/.cursor/` (same behavior everywhere). `config.md` and templates are project-local (different test commands, different TDD sections per project). The agents read `.sdlc/config.md` from the project root at runtime, so they adapt to whatever project they're invoked in.

#### Precedence rules

When the same agent name exists in multiple locations, Cursor resolves conflicts:

1. `.cursor/agents/` — **highest priority** (project-level)
2. `~/.cursor/agents/` — user-level fallback
3. `.claude/agents/` / `.codex/agents/` — compatibility fallback

This means you can install agents globally but override a specific agent per-project by placing a file with the same name in the project's `.cursor/agents/` directory.

### Recommended Setup

**For individual developers** — install agents and **skills** globally, add `.sdlc/` per project:

```bash
# One-time global setup
mkdir -p ~/.cursor/agents ~/.cursor/skills
cp .cursor/agents/*.md ~/.cursor/agents/
# Skills (one subfolder per skill — see "Cursor skills" above)
test -d .cursor/skills && cp -r .cursor/skills/* ~/.cursor/skills/

# Per project: just add the config and templates
cp -r .sdlc/ /path/to/your/project/.sdlc/
# Then edit .sdlc/config.md for that project's stack
```

**For teams** — install everything at project level and check into version control:

```bash
cp -r .cursor/ /path/to/your/project/.cursor/
cp -r .sdlc/ /path/to/your/project/.sdlc/
# Edit .sdlc/config.md, commit, push
```

Everyone on the team gets the same agents, **skills**, templates, and config from `git pull`.

## Customizing for Your Project

### Stack Configuration

Edit `.sdlc/config.md` — the Verifier reads test/lint/build commands from here, and the Coder reads conventions.

### Agent Prompts

Each agent in `.cursor/agents/` is a plain Markdown file. Edit them to:

- Add project-specific rules to the Coder (e.g., "always use repository pattern")
- Adjust Reviewer severity thresholds
- Add domain-specific checklists to the Architect
- Tweak the Evaluator's adversarial tone or focus areas

### Templates

Templates in `.sdlc/templates/` define the output format. Modify them to:

- Add sections specific to your domain (e.g., compliance, accessibility)
- Change the review severity levels
- Add required fields to the TDD
- Adjust the Evaluator's output structure

### Adding New Agents

Create a new `.md` file in `.cursor/agents/` (project) or `~/.cursor/agents/` (global):

```markdown
---
name: my-custom-agent
description: What this agent does and when to use it.
model: fast
readonly: true
---

Agent instructions here...
```

The Cursor agent will automatically detect it and delegate based on the description.

## File Reference

### `.sdlc/templates/task.md` — The Most Critical File

The task template is the linchpin of the framework. A well-written task:

- Carries requirements and behavior without relying on the TDD or other tasks in the Coder prompt (the Coder can still open the repo)
- Uses Gherkin scenarios that map directly to test cases
- Includes inline code snippets from the existing codebase
- Specifies exact file paths to modify
- Lists dependencies with their expected interfaces

The `examples/oauth2/tasks/T001-add-oauth-providers.md` file demonstrates a fully populated task.

### `.sdlc/templates/epic.md` — Epic and Mermaid dependency graph

The Planner uses this for `01-epic.md`: task list, a fenced Mermaid diagram of the full DAG (edge direction: prerequisite → dependent), optional `classDef` colors per parallel stream with a neutral style for merge tasks, and a legend.

### `.sdlc/templates/evaluation.md` — The Evaluator's Output Format

The evaluation template structures the Evaluator's critique into: Alignment Check, Executive Summary, Critical Vulnerabilities & Blind Spots, Trade-off Analysis, Alternative Approaches, Hard Questions, and a Verdict.

The `examples/oauth2/evaluations/00-tdd-evaluation.md` file demonstrates a full evaluation showing how the Evaluator critiques a real TDD.

### `.sdlc/config.md` — Project Configuration

The Verifier reads command configurations from here. If a command is missing or set to `none`, that check is skipped. At minimum, `test_command` and `lint_command` should be set.

### `.cursor/skills/` — Workflow (phases and gates)

SDLC procedure (paths, Evaluator, Planner, implement loop, human gates) lives in **`sdlc-tdd`**, **`sdlc-plan`**, **`sdlc-implement`**, and **`sdlc-archive`** under [`.cursor/skills/`](#cursor-skills). Invoke or follow those skills instead of a separate always-on workflow rule.

## Requirements

- [Cursor](https://cursor.com) with agent mode enabled
- A project with a configured test runner and linter
- No additional dependencies — this is pure configuration

## Troubleshooting

If something is wrong and you want a **clean reinstall**, remove the **Cursor-side** copy of the framework and copy it again. **Keep** **`.sdlc/`** so you do not lose [`config.md`](.sdlc/config.md), [`templates/`](.sdlc/templates/), or work under [`.sdlc/projects/`](.sdlc/projects/).

### Project-level (`.cursor/` in your app repo)

Replace both paths with your clone of **orchestration-framework** and your app’s root. Do **not** run `rm` on `.sdlc`.

```bash
rm -rf /path/to/your/project/.cursor
cp -r /path/to/orchestration-framework/.cursor/ /path/to/your/project/.cursor/
```

### User-level (`~/.cursor/`) — only if you installed agents or skills globally

Manually delete each framework skill directory you had installed under **`~/.cursor/skills/`** (for example the **`sdlc-archive`** folder) using Finder or another file manager, so you do not remove unrelated skills by accident. Then run the `cp` lines from a clone of **orchestration-framework** (the `cd` sets that up in one place):

```bash
cd /path/to/orchestration-framework

rm -f ~/.cursor/agents/sdlc-*.md

mkdir -p ~/.cursor/agents ~/.cursor/skills
cp .cursor/agents/*.md ~/.cursor/agents/
test -d .cursor/skills && cp -r .cursor/skills/* ~/.cursor/skills/
```

Then, for each app, only refresh **`.cursor/`** if needed (use the project-level block) or ensure **`.sdlc/`** exists per [Quick Start](#quick-start).

## Acknowledgments

Built on [Cursor's subagent architecture](https://cursor.com/docs/subagents) using the orchestrator pattern with context isolation.