# Agent Orchestration Framework

An agent-driven SDLC framework for [Cursor](https://cursor.com). Define features, decompose them into testable tasks, implement with autonomous agents, and enforce quality through parallel review and verification — all controlled by human gates.

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
          [Coder]    [Coder]    [Coder]     ← each reads ONE task only
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

| Agent | Role | Reads | Writes | Model | Readonly |
|---|---|---|---|---|---|
| **Architect** | Produces Technical Design Document from requirements | Requirements + codebase exploration | TDD at `.sdlc/projects/<slug>/00-tdd.md` | inherit | no |
| **Evaluator** | Critically evaluates TDDs — finds flaws, blind spots, trade-offs | TDD + codebase exploration | Returns critique as text (main agent persists) | inherit | yes |
| **Planner** | Decomposes TDD into self-contained Gherkin-based tasks | TDD only | Epic at `01-epic.md` + tasks at `.sdlc/projects/<slug>/tasks/T<id>-*.md` | inherit | no |
| **Coder** | Implements task + writes tests from Gherkin scenarios | ONE task + config | Production code + tests | inherit | no |
| **Reviewer** | Reviews code quality, bugs, scenario coverage | ONE task + code diff | Review report | inherit | yes |
| **Verifier** | Runs tests, lint, typecheck, build mechanically | Config only | Verification report | fast | yes |

### Context Isolation

Each agent operates with strict context boundaries:

- **Architect** → reads requirements and codebase, writes TDD
- **Evaluator** → reads TDD and codebase, returns critique, never edits files
- **Planner** → reads TDD only, writes self-contained tasks
- **Coder** → reads ONE task file only, never sees TDD or other tasks
- **Reviewer** → reads ONE task + code changes, never edits code
- **Verifier** → reads config only, has no knowledge of tasks or features

The Planner is the critical translation layer. It must write tasks detailed enough that the Coder never needs the TDD.

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

**Path A — Generate a new TDD:**

```
/sdlc-architect Create a TDD for adding OAuth2 login with Google and GitHub
```

**Path B — Evaluate an existing TDD:**

```
/sdlc-evaluator Evaluate the TDD at .sdlc/projects/oauth2/00-tdd.md
```

## Workflow

### Phase 1: Design

#### Path A: Generate TDD

```
> /sdlc-architect Create a TDD for <feature description>
```

The Architect explores your codebase and writes a TDD to `.sdlc/projects/<slug>/00-tdd.md`.

#### Path B: Bring your own TDD

Place your existing TDD at `.sdlc/projects/<slug>/00-tdd.md`.

#### Both paths: Evaluate

```
> /sdlc-evaluator Evaluate .sdlc/projects/<slug>/00-tdd.md
```

The Evaluator critically examines the TDD, validates claims against the codebase, and returns a structured critique. If the verdict is `needs-revision`, the human revises the TDD and the Evaluator is re-invoked.

**Human gate: Review the evaluation and approve the TDD.**

### Phase 2: Planning

```
> /sdlc-planner Decompose the TDD at .sdlc/projects/<slug>/00-tdd.md into tasks
```

The Planner reads the TDD and creates self-contained tasks with Gherkin scenarios in `.sdlc/projects/<slug>/tasks/`, and writes `01-epic.md` with a **Mermaid task dependency graph** (following `.sdlc/templates/epic.md`). When the plan has parallel dependency streams, the diagram **color-codes** each stream and includes a short **legend**; linear plans use a single node style.

**Human gate: Review and approve the task plan.**

### Phase 3: Implementation Loop

For each task (respect dependency ordering):

```
> Implement T001
```

The main Cursor agent will:

1. Invoke `sdlc-coder` to implement the task and write tests
2. Launch `sdlc-reviewer` and `sdlc-verifier` **in parallel**
3. If either fails, re-invoke the Coder with the feedback
4. When both pass, present results for human sign-off

**Human gate: Approve the completed task.**

You can also run individual agents explicitly:

```
> /sdlc-coder Implement .sdlc/projects/<slug>/tasks/T001-<name>.md
> /sdlc-reviewer Review .sdlc/projects/<slug>/tasks/T001-<name>.md
> /sdlc-verifier Verify T001
```

### Phase 4: Completion

After all tasks pass review and verification, the feature is ready for final human review and merge.

### Archiving a project (optional)

When a feature is finished or you want a **lean** per-slug folder under `.sdlc/projects/`, use the **archive** skill in [`.cursor/skills/archive/SKILL.md`](.cursor/skills/archive/SKILL.md). It is included when you copy the full [`.cursor/`](.cursor/) tree (see [Quick Start](#1-copy-into-your-project)); optional details live in [`.cursor/skills/archive/reference.md`](.cursor/skills/archive/reference.md).

**Installing the skill (project vs global).** Cursor loads skills from **`.cursor/skills/<name>/`** in the open workspace, or from **`~/.cursor/skills/<name>/`** for all projects. If you only copied [`.cursor/agents/`](.cursor/agents/) and not the rest of [`.cursor/`](.cursor/), add the skill to the repo: copy this repo’s **`.cursor/skills/archive/`** into **`your-project/.cursor/skills/archive/`** (include `SKILL.md` and `reference.md`). To use the same skill in every repository without per-project files:

```bash
mkdir -p ~/.cursor/skills
cp -r /path/to/orchestration-framework/.cursor/skills/archive ~/.cursor/skills/
```

**How to use it.** In Cursor, ask the agent in plain language, for example: *Archive SDLC project `my-feature`*, *archive project oauth2*, or *clean up the .sdlc project for that slug*. The agent follows the skill: confirm the slug, confirm that supporting files will be **removed** after a summary is written, then execute the steps in the skill.

**What you get.**

| Location | After a successful archive |
|----------|----------------------------|
| **`.sdlc/projects/<slug>/`** | Only **`00-tdd.md`** (unchanged) and **`project-summary.md`** (consolidated summary: epic text, evaluation highlights, one section per task with review/verify outcomes) |
| **`.sdlc/archive/<slug>/<timestamp>/`** | **`dependency-graph.md`** — full Mermaid task dependency graph and legend copied from `01-epic.md`; **`project-summary.md`** — same content as the copy next to the TDD (self-contained snapshot) |

**What goes away** from `.sdlc/projects/<slug>/` after the two archive files are written: **`01-epic.md`**, **`tasks/`**, **`evaluations/`**, **`reviews/`**, **`verifications/`**, and any other project-local supporting **`*.md`**, except the TDD and `project-summary.md`. The framework’s **`.sdlc/templates/`** directory and other slugs’ folders are **not** modified.

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
  rules/
    sdlc-workflow.mdc              # Workflow enforcement rules
  skills/
    archive/                       # Optional: clean up a finished project folder
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
  archive/                         # Optional archive runs (gitignored)
    <slug>/
      <timestamp>/
        dependency-graph.md        # Mermaid + legend (from 01-epic)
        project-summary.md         # Copy of the summary next to the TDD
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

The workflow rule in `.cursor/rules/sdlc-workflow.mdc` prevents the agent from proceeding past these gates without explicit human approval.

## Installation Scopes

Cursor supports two scopes for agents and rules: **project-level** and **user-level**.

### Project-Level (per repo)

This is what the Quick Start section covers. Agents and config live inside the project:

```
your-project/
  .cursor/
    agents/           ← project-scoped agents
    rules/            ← project-scoped rules
  .sdlc/
    config.md         ← project-specific config
    templates/        ← project-specific templates
```

Use this when:
- The project has specific conventions, test frameworks, or architecture patterns
- You want the framework checked into version control for the whole team
- Templates need to be customized for the project's domain

### User-Level (global, all projects)

Agents and rules can also be installed globally so they're available in **every** project without copying files:

```
~/.cursor/
  agents/              ← user-scoped agents (all projects)
    sdlc-architect.md
    sdlc-evaluator.md
    sdlc-planner.md
    sdlc-coder.md
    sdlc-reviewer.md
    sdlc-verifier.md
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

| Scope | What to install | Why |
|---|---|---|
| **User-level** (`~/.cursor/agents/`) | All 6 agents | Available everywhere, no per-project copy |
| **User-level** (`~/.cursor/rules/`) | Workflow rule | Enforces the SDLC process in every project |
| **Project-level** (`.sdlc/`) | `config.md` + templates | Project-specific stack, commands, and output formats |

Agents are global (same behavior everywhere), but `config.md` and templates are project-local (different test commands, different TDD sections per project). This is the intended design — the agents read `.sdlc/config.md` from the project root at runtime, so they adapt to whatever project they're invoked in.

#### Precedence rules

When the same agent name exists in multiple locations, Cursor resolves conflicts:

1. `.cursor/agents/` — **highest priority** (project-level)
2. `~/.cursor/agents/` — user-level fallback
3. `.claude/agents/` / `.codex/agents/` — compatibility fallback

This means you can install agents globally but override a specific agent per-project by placing a file with the same name in the project's `.cursor/agents/` directory.

### Recommended Setup

**For individual developers** — install agents + workflow rule globally, add `.sdlc/` per project:

```bash
# One-time global setup
mkdir -p ~/.cursor/agents ~/.cursor/rules
cp .cursor/agents/*.md ~/.cursor/agents/
cp .cursor/rules/sdlc-workflow.mdc ~/.cursor/rules/

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

Everyone on the team gets the same agents, templates, and config from `git pull`.

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

- Is completely self-contained — no external context needed
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

### `.cursor/rules/sdlc-workflow.mdc` — Workflow Enforcement

This Cursor rule file instructs the main Cursor agent on the SDLC process. It enforces:
- Two entry paths (generate TDD vs. bring your own)
- Mandatory Evaluator step before planning
- The fork-join Review + Verify loop
- Human gate requirements
- Context isolation between agents
- The correct agent invocation order

## Requirements

- [Cursor](https://cursor.com) with agent mode enabled
- A project with a configured test runner and linter
- No additional dependencies — this is pure configuration

## Acknowledgments

Built on [Cursor's subagent architecture](https://cursor.com/docs/subagents) using the orchestrator pattern with context isolation.
