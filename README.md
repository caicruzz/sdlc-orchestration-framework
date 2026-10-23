# Agent Orchestration Framework

An agent-driven SDLC framework for [Cursor](https://cursor.com) and [Claude Code](https://claude.com/claude-code). Define features, decompose them into testable tasks, implement with autonomous agents, and enforce quality through parallel review and verification — all controlled by human gates. The agents and **Agent Skills** are written once, tool-neutral, in `.sdlc/framework/`; `.sdlc/sync.sh` generates the `.cursor/` and `.claude/` adapters each tool loads (see [Supported tools](#supported-tools)).

## How It Works

```
Path A: No TDD exists             Path B: TDD already exists

   Requirements                         Existing TDD
        │                                    │
        ▼                                    │
  ┌>[Architect]                              │
  │ generates/refines TDD                    │
  │     │                                    │
  │     └──────────┬─────────────────────────┘
  │                ▼
  │           [Evaluator]  ← red teams the TDD
  │                │
  │                ▼
  └───────(No)── TDD Approved?
                   │
                 (Yes)
                   │
                   ▼
         Human Gate 1: TDD Approval
                   │
                   ▼
               [Planner]
                   │
     creates tasks with Gherkin scenarios
                   │
                   ▼
         Human Gate 2: Review Task Plan
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
          Parallel Review Fork                   │
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
         Human Gate 3: Final Sign-off
                   │
                   ▼
                 Done
```

## Agents


| Agent         | Role                                                             | Reads                               | Writes                                                                   | Model   | Readonly |
| ------------- | ---------------------------------------------------------------- | ----------------------------------- | ------------------------------------------------------------------------ | ------- | -------- |
| **Architect** | Produces Technical Design Document from requirements             | Requirements + codebase exploration | TDD at `.sdlc/projects/<slug>/00-tdd.md`                                 | inherit | no       |
| **Evaluator** | Critically evaluates TDDs — finds flaws, blind spots, trade-offs | TDD + codebase exploration          | Returns critique as text (main agent persists)                           | inherit | yes      |
| **Planner**   | Decomposes TDD into self-contained Gherkin-based tasks           | TDD only                            | Epic at `01-epic.md` + tasks at `.sdlc/projects/<slug>/tasks/T<id>-*.md` | inherit | no       |
| **Coder**     | Implements task + writes tests from Gherkin scenarios            | Task file + config (+ full repo)    | Production code + tests                                                  | inherit | no       |
| **Reviewer**  | Reviews code quality, bugs, scenario coverage                    | ONE task + code diff                | Returns review report (main agent persists)                              | inherit | yes      |
| **Verifier**  | Runs tests, lint, typecheck, build mechanically                  | Config only                         | Returns verification report (main agent persists)                        | inherit | yes      |


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

### 1. Copy into your project and generate adapters

```bash
cp -r .sdlc/ /path/to/your/project/.sdlc/
/path/to/your/project/.sdlc/sync.sh            # writes .cursor/ and .claude/
# or: .sdlc/sync.sh --target cursor | --target claude
```

`.sdlc/framework/` holds the canonical agents and skills; `sync.sh` writes the tool-specific copies. It only ever removes files it generated (they carry a `Generated by .sdlc/sync.sh` marker) and overwrites same-named `sdlc-*` agents and skill files; your other agents and skills are untouched.

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

Use the [`sdlc-tdd`](.sdlc/framework/skills/sdlc-tdd/SKILL.md) skill in natural language (Cursor or Claude Code)—for example: *Run Phase 1 SDLC for OAuth2 with Google and GitHub*, or *Evaluate the TDD at `.sdlc/projects/oauth2/00-tdd.md`*. The skill covers Architect (when needed), mandatory Evaluator, persisting `**.sdlc/projects/<slug>/evaluations/00-tdd-evaluation.md**`, and the human approval gate; it documents when the subagents are invoked.

## Workflow

### Phase 1: Design

Follow `**[sdlc-tdd](.sdlc/framework/skills/sdlc-tdd/SKILL.md)**` end-to-end.

#### Path A: Generate TDD

The skill has the **Architect** explore the codebase and write `**.sdlc/projects/<slug>/00-tdd.md`** from your feature description or requirements.

#### Path B: Bring your own TDD

Place your existing TDD at `**.sdlc/projects/<slug>/00-tdd.md`**, then continue with the same skill (skip regeneration unless you explicitly want a refresh).

#### Both paths: Evaluate

The skill runs the **Evaluator** on `**.sdlc/projects/<slug>/00-tdd.md`**. It critically examines the TDD, validates claims against the codebase, and returns a structured critique. If the verdict is `needs-revision`, the human revises the TDD and evaluation runs again per the skill.

**Human gate: Review the evaluation and approve the TDD.**

The skill stops before Phase 2 until the human approves.

### Phase 2: Planning

Follow `**[sdlc-plan](.sdlc/framework/skills/sdlc-plan/SKILL.md)`** after the TDD is human-approved. The skill uses the **Planner** to read `**.sdlc/projects/<slug>/00-tdd.md`** and produce self-contained tasks with Gherkin scenarios under `**.sdlc/projects/<slug>/tasks/`**, plus `**01-epic.md`** with a Mermaid task dependency graph (following `**.sdlc/templates/epic.md**`). When the plan has parallel dependency streams, the diagram **color-codes** each stream and includes a short **legend**; linear plans use a single node style.

**Human gate: Review and approve the task plan.**

The skill requires `**## Task dependency graph`** in `**01-epic.md`** and stops at human approval before implementation; subagent invocation details live in the skill file.

### Phase 3: Implementation Loop

For each task (respect dependency ordering from `**01-epic.md`**), follow `**[sdlc-implement](.sdlc/framework/skills/sdlc-implement/SKILL.md)`**—for example: *Implement T001 for `<slug>`* or *run the SDLC implement loop for the next task*.

The skill defines the loop: **Coder** implements from the task file and Gherkin; **Reviewer** and **Verifier** run **in parallel**; failures get **appended** feedback and another Coder pass; when both pass, results go to the human. Reviewer uses the task path; Verifier uses the task ID and `**.sdlc/config.md`** only. Every scenario must map to tests; ordering follows the epic DAG.

**Human gate: Approve the completed task.**

For low-level or custom orchestration you can invoke the `sdlc-coder`, `sdlc-reviewer`, and `sdlc-verifier` subagents directly (see [Supported tools](#supported-tools)); prefer driving work through `sdlc-implement` so gates and parallelism stay consistent.

### Phase 4: Completion

After all tasks pass review and verification, the feature is ready for final human review and merge.

### Archiving a project

When a feature is finished, use the [`sdlc-archive`](.sdlc/framework/skills/sdlc-archive/SKILL.md) skill; more detail in [`reference.md`](.sdlc/framework/skills/sdlc-archive/reference.md).

**How to use it.** In Cursor or Claude Code, ask the agent in plain language, for example: *Archive SDLC project `my-feature`*, archive project `oauth2*`, or clean up the .sdlc project for that slug. The agent follows the skill: confirm the slug, that the **TDD will move** into the archive, and that the `**projects/<slug>*` tree will be removed.

**What you get.** One self-contained run folder, **no duplicate `project-summary`**, and the slug directory under `projects/` is removed (you can start a new feature with the same slug later if needed).


| Location                                | After a successful archive                                                                                                                                                                                                                               |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `**.sdlc/archive/<slug>/<timestamp>/**` | `**00-tdd.md**` — moved from `projects/` (not edited), `**project-summary.md**` — single summary (epic, evaluation highlights, one section per task with review/verify), `**dependency-graph.md**` — full Mermaid + legend from `01-epic` when available |
| `**.sdlc/projects/<slug>/**`            | **Removed** (empty after the move and cleanup)                                                                                                                                                                                                           |


**What stays** elsewhere: all of `**.sdlc/`** except that slug (config, templates, other slugs’ folders). The framework’s `**.sdlc/templates/`** is never deleted.

**Git.** In this repository, `**.sdlc/projects/`*** and `**.sdlc/archive/`*** are **gitignored** (with `.gitkeep` placeholders) so local SDLC and archive output stay off the default commit unless you opt in.

## Project Structure

```
.sdlc/
  sync.sh                          # Generates .cursor/ and .claude/ adapters
  framework/                       # Canonical, tool-neutral sources (edit these)
    agents/
      sdlc-architect.md
      sdlc-evaluator.md            # TDD red team
      sdlc-planner.md
      sdlc-coder.md
      sdlc-reviewer.md
      sdlc-verifier.md
    skills/                        # Core: packaged workflows + SDLC phases
      sdlc-tdd/SKILL.md            # Phase 1: TDD paths + Evaluator + approval gate
      sdlc-plan/SKILL.md           # Phase 2: Planner, epic + task DAG, approval gate
      sdlc-implement/SKILL.md      # Phase 3: Coder, parallel review/verify, per-task loop
      sdlc-archive/                # Clean up a finished .sdlc/projects slug
        SKILL.md
        reference.md
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
        T001-review.md             # Reviewer report (persisted by main agent)
      verifications/
        T001-verify.md             # Verifier report (persisted by main agent)
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
.cursor/                           # GENERATED by sync.sh for Cursor
  agents/sdlc-*.md
  skills/sdlc-*/
.claude/                           # GENERATED by sync.sh for Claude Code
  agents/sdlc-*.md
  skills/sdlc-*/
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

Use the `sdlc-tdd`, `sdlc-plan`, and `sdlc-implement` skills so the orchestrator follows phases, parallel review/verify, and these gates explicitly—skills replace a separate always-on workflow rule.

## Supported tools

The framework targets **Cursor** and **Claude Code**. Prompts, skills, and templates are shared; only the thin adapter layer differs, and `sync.sh` generates it.

| | Cursor | Claude Code |
|---|---|---|
| Agents | `.cursor/agents/sdlc-*.md` | `.claude/agents/sdlc-*.md` |
| Skills | `.cursor/skills/sdlc-*/` | `.claude/skills/sdlc-*/` |
| Read-only agents | `readonly: true` frontmatter | `tools: Read, Grep, Glob` allowlist (no Edit/Write); `+ Bash` when `shell: true` |
| Invoking a subagent | Delegate by name, e.g. `/sdlc-coder <task path>` | Agent tool with `subagent_type: sdlc-coder` |

### Canonical frontmatter

Agents in `.sdlc/framework/agents/` use only tool-neutral fields:

```yaml
---
name: sdlc-reviewer
description: What the agent does and when to use it.
model: inherit
readonly: true      # mapped per tool by sync.sh
shell: true         # optional; read-only agent needs to run commands (adds Bash in Claude Code)
---
```

Read-only agents (Evaluator, Reviewer, Verifier) never write files: they return their report and the orchestrating skill persists it. In Claude Code, Edit/Write are removed from all three, and the Evaluator has no shell at all, so it is hard read-only. The Reviewer (`git diff`) and Verifier (test/lint/build commands) need `Bash`, which can still write files, so for them read-only also relies on the prompt.

### `sync.sh` usage

```bash
.sdlc/sync.sh                      # both tools, into the folder containing .sdlc/
.sdlc/sync.sh --target claude      # one tool only
.sdlc/sync.sh --dest "$HOME"       # user-level install (~/.cursor, ~/.claude)
.sdlc/sync.sh --check              # exit 1 if generated files are stale (CI-friendly)
```

Re-run it whenever you change anything under `.sdlc/framework/`. The generated files in this repository are committed so a plain copy still works, and CI (`.github/workflows/sync-check.yml`) runs `--check` on every pull request to catch drift.

### Project-level vs user-level

- **Project-level** (default): `.sdlc/` plus the generated `.cursor/` and `.claude/` live in the repo — commit them so everyone gets the same setup.
- **User-level**: run `sync.sh --dest "$HOME"` once to make the agents and skills available in every repo, then copy only `.sdlc/config.md` and `.sdlc/templates/` into each project. Project-level agents take precedence over user-level agents with the same name in both tools.

Cursor also reads `.claude/agents/` as a compatibility fallback; when both exist, `.cursor/agents/` wins, so Cursor keeps its own `readonly` frontmatter.

## Customizing for Your Project

### Stack Configuration

Edit `.sdlc/config.md` — the Verifier reads test/lint/build commands from here, and the Coder reads conventions.

### Agent Prompts

Each agent in `.sdlc/framework/agents/` is a plain Markdown file. Edit them (then re-run `.sdlc/sync.sh`) to:

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

Create a new `.md` file in `.sdlc/framework/agents/` using the [canonical frontmatter](#canonical-frontmatter), then run `.sdlc/sync.sh`. New skills go in `.sdlc/framework/skills/<skill-name>/SKILL.md` (the frontmatter `name` must match the folder name). Each tool detects the generated files and delegates based on the description.

## File Reference

### `.sdlc/templates/task.md` — The Most Critical File

The task template is the linchpin of the framework. A well-written task:

- States a one-sentence business **Objective**
- Uses **Acceptance Criteria** (Gherkin scenarios) as the primary spec — mappable directly to tests
- Keeps technical detail in optional **Dev Notes** (paths, snippets, constraints, dependency interfaces)
- Lists dependencies briefly without front-loading implementation detail

The `examples/oauth2/tasks/T001-add-oauth-providers.md` file demonstrates a fully populated task.

### `.sdlc/templates/epic.md` — Epic and Mermaid dependency graph

The Planner uses this for `01-epic.md`: task list, a fenced Mermaid diagram of the full DAG (edge direction: prerequisite → dependent), optional `classDef` colors per parallel stream with a neutral style for merge tasks, and a legend.

### `.sdlc/templates/evaluation.md` — The Evaluator's Output Format

The evaluation template structures the Evaluator's critique into: Alignment Check, Executive Summary, Critical Vulnerabilities & Blind Spots, Trade-off Analysis, Alternative Approaches, Hard Questions, and a Verdict.

The `examples/oauth2/evaluations/00-tdd-evaluation.md` file demonstrates a full evaluation showing how the Evaluator critiques a real TDD.

### `.sdlc/config.md` — Project Configuration

The Verifier reads command configurations from here. If a command is missing or set to `none`, that check is skipped. At minimum, `test_command` and `lint_command` should be set.

### `.sdlc/framework/skills/` — Workflow (phases and gates)

SDLC procedure (paths, Evaluator, Planner, implement loop, human gates) lives in the `sdlc-tdd`, `sdlc-plan`, `sdlc-implement`, and `sdlc-archive` skills. Invoke or follow those skills instead of a separate always-on workflow rule.

## Requirements

- [Cursor](https://cursor.com) with agent mode, and/or [Claude Code](https://claude.com/claude-code)
- `bash` (3.2+) to run `.sdlc/sync.sh`
- A project with a configured test runner and linter
- No other dependencies — this is pure configuration

## Troubleshooting

For a clean reinstall, re-run the sync script. It replaces only the files it generated and leaves your own agents and skills alone, and it never touches `.sdlc/config.md`, `.sdlc/templates/`, or `.sdlc/projects/`.

```bash
.sdlc/sync.sh                     # project-level
.sdlc/sync.sh --dest "$HOME"      # user-level, if you installed globally
```

If you installed an older version by copying `.cursor/` by hand, those files have no generated marker; `sync.sh` overwrites same-named `sdlc-*` files but will not delete ones that no longer exist in the framework, so remove any stale `sdlc-*` agents or skills manually once.

## Acknowledgments

Built on [Agent Skills](https://cursor.com/docs/skills) and subagents in [Cursor](https://cursor.com/docs/subagents) and [Claude Code](https://docs.claude.com/en/docs/claude-code/sub-agents), using the orchestrator pattern with context isolation.
