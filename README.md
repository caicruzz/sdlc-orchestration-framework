# soloAIfactory

**Run a whole AI software factory as a team of one.** A line of specialized agents designs, plans, builds and inspects your software in [Claude Code](https://claude.com/claude-code), [Cursor](https://cursor.com) and [OpenCode](https://opencode.ai), with human quality gates between every stage.

You bring the requirements and make the calls at each gate. The factory turns them into a Design Doc, red-teams it, breaks it into testable work, builds each piece, and puts every piece through parallel review and verification before it reaches you. The agents and **Agent Skills** ship ready to use for each supported harness in `.ai-factory/harnesses/`, and your AI agent installs them by following [`install-factory-instructions.md`](install-factory-instructions.md) (see [Supported tools](#-supported-tools)).

## ⚙️ How It Works

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
   Ready tasks (all prerequisites done) <─────────────┐
                   │                                  │
     run in parallel, each on its own                 │
     branch + worktree (max_concurrent_tasks)         │
                   │                                  │
                   ▼                                  │
               [Coder] <────────────────┐             │
           implements & tests           │             │
                   │                    │             │
           ┌───────┴───────┐            │             │
           ▼               ▼            │             │
      [Reviewer]      [Verifier]        │             │
     code quality   tests/lint/build    │             │
           │               │            │             │
           └───────┬───────┘            │             │
                   ▼                    │             │
              Both pass? ──(No: retry)──┘             │
                   │   at max_iterations:             │
                 (Yes) blocked + escalated to you     │
                   │                                  │
                   ▼                                  │
       PR per task into epic branch                   │
                   │                                  │
                   ▼                                  │
  Quality Gate 3: you merge the task PR ──────────────┘
                   │   (unblocks dependent tasks)
                   ▼
  Quality Gate 4: you merge the epic PR → Ship
```

## 🏭 The Line: Agents as Stations

| Station       | Role                                                                    | Reads                               | Writes                                                                         | Model   | Readonly |
| ------------- | ----------------------------------------------------------------------- | ----------------------------------- | ------------------------------------------------------------------------------ | ------- | -------- |
| **Architect** | Produces the Design Doc from requirements                               | Requirements + codebase exploration | Design Doc at `.ai-factory/projects/<slug>/00-design.md`                       | inherit | no       |
| **Evaluator** | Critically evaluates Design Docs — finds flaws, blind spots, trade-offs | Design Doc + codebase exploration   | Returns critique as text (main agent persists)                                 | inherit | yes      |
| **Planner**   | Decomposes the Design Doc into self-contained Gherkin-based tasks       | Design Doc only                     | Epic at `01-epic.md` + tasks at `.ai-factory/projects/<slug>/tasks/T<id>-*.md` | inherit | no       |
| **Coder**     | Implements task + writes tests from Gherkin scenarios                   | Task file + config (+ full repo in its worktree) | Production code + tests, committed on the task branch                 | inherit | no       |
| **Reviewer**  | Reviews code quality, bugs, scenario coverage                           | ONE task + code diff                | Returns review report (main agent persists)                                    | inherit | yes      |
| **Verifier**  | Runs tests, lint, typecheck, build mechanically                         | Config + task worktree              | Returns verification report (main agent persists)                              | inherit | yes      |

### Context Isolation

Like stations on a production line, each agent receives only the inputs it needs and hands off a defined output:

- **Architect** → reads requirements and codebase, writes the Design Doc
- **Evaluator** → reads the Design Doc and codebase, returns critique, never edits files
- **Planner** → reads the Design Doc only, writes self-contained tasks
- **Coder** → invoked with one task file + config + its task worktree (Design Doc/epic not in prompt); may read and edit anywhere in that worktree per task scope
- **Reviewer** → reads ONE task + the task branch's diff, never edits code
- **Verifier** → reads config only and runs it in the task worktree, has no knowledge of tasks or features

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

## 🚀 Quick Start

### 1. Ask your AI agent to install it

In your project, ask the agent in your harness (Claude Code, Cursor or OpenCode):

```text
Follow https://github.com/caicruzz/soloAIfactory/blob/main/install-factory-instructions.md to install Solo AI Factory.
```

The agent identifies its harness, asks whether to install for this project or for your user, lets you confirm or change each agent's model, copies that harness's `factory-*` agents and skills from `.ai-factory/harnesses/<harness>/`, and copies `config.md` and `templates/` into your project's `.ai-factory/` without overwriting anything. It also offers to add a `factory-checks` GitHub Actions workflow that runs your `config.md` checks on every pull request. It only ever touches `factory-*` agents and skills, and asks before overwriting any you customized; your other agents and skills are untouched. On a reinstall it lists templates that differ from the factory copy and offers to update them.

### 2. Configure your project

Edit `.ai-factory/config.md` to match your tech stack:

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

Use the [`factory-design`](.ai-factory/harnesses/claude/skills/factory-design/SKILL.md) skill in natural language (Claude Code, Cursor or OpenCode), for example: *Run the design stage for OAuth2 with Google and GitHub*, or *Evaluate the Design Doc at `.ai-factory/projects/oauth2/00-design.md`*. The skill covers the Architect (when needed), the mandatory Evaluator, persisting `.ai-factory/projects/<slug>/evaluations/00-design-evaluation.md`, and the human quality gate; it documents when the subagents are invoked.

## 🔄 Workflow

The factory runs in four stages, each ending at a human quality gate.

### 📐 Stage 1: Design

Follow [`factory-design`](.ai-factory/harnesses/claude/skills/factory-design/SKILL.md) end-to-end.

#### Path A: Generate the Design Doc

The skill has the **Architect** explore the codebase and write `.ai-factory/projects/<slug>/00-design.md` from your feature description or requirements.

#### Path B: Bring your own Design Doc

Place your existing Design Doc at `.ai-factory/projects/<slug>/00-design.md`, then continue with the same skill (skip regeneration unless you explicitly want a refresh).

#### Both paths: Evaluate

The skill runs the **Evaluator** on `.ai-factory/projects/<slug>/00-design.md`. It critically examines the Design Doc, validates claims against the codebase, and returns a structured critique. If the verdict is `needs-revision`, the human revises the Design Doc and evaluation runs again per the skill.

**Quality gate: Review the evaluation and approve the Design Doc.**

The skill stops before Stage 2 until the human approves.

### 🗺️ Stage 2: Plan

Follow [`factory-plan`](.ai-factory/harnesses/claude/skills/factory-plan/SKILL.md) after the Design Doc is human-approved. The skill uses the **Planner** to read `.ai-factory/projects/<slug>/00-design.md` and produce self-contained tasks with Gherkin scenarios under `.ai-factory/projects/<slug>/tasks/`, plus `01-epic.md` with a Mermaid task dependency graph (following `.ai-factory/templates/epic.md`). When the plan has parallel dependency streams, the diagram **color-codes** each stream and includes a short **legend**; linear plans use a single node style.

**Quality gate: Review and approve the task plan.**

The skill requires `## Task dependency graph` in `01-epic.md` and stops at human approval before implementation; subagent invocation details live in the skill file.

### 🔨 Stage 3: Build

Follow [`factory-build`](.ai-factory/harnesses/claude/skills/factory-build/SKILL.md), for example: *Build the epic for `<slug>`*, *Implement T001 for `<slug>`*, or *continue the build, T002's PR is merged*.

The skill creates an epic branch `factory/<slug>` from your base branch, then runs every **ready** task (all prerequisites `done`) at the same time, up to `max_concurrent_tasks`. Each task gets its own branch `factory/<slug>/T<id>` and git worktree, so parallel Coders never touch each other's files. Per task, the **Coder** implements from the task file and Gherkin; **Reviewer** and **Verifier** run **in parallel** in that worktree; failures get **appended** feedback and another Coder pass. After `max_iterations` failed passes the task is set `blocked` with an escalation summary and handed to you, while other tasks keep going. When both pass, the skill pushes the task branch and opens a PR into the epic branch. Task files and reports stay in your main checkout as the single source of truth.

**Quality gate: merge the task PR.** Merging is your sign-off: the task becomes `done`, its worktree is removed, and tasks that depended on it become ready and branch from the updated epic branch. Merge conflicts are reported to you, never resolved automatically, and nothing is ever pushed to your default branch.

**Long builds and context.** The orchestrator saves `.ai-factory/projects/<slug>/build-state.md` at every checkpoint. After `handoff_after_rounds` Review + Verify rounds, or when you ask, it finishes the steps in flight, marks the state `handoff-pending` and asks you to clear the conversation (`/clear` in Claude Code, a new chat in Cursor, `/new` in OpenCode) and say *resume the factory build for `<slug>`*. The fresh orchestrator rebuilds its picture from the state file and task files and carries on. The installer also offers optional context hooks that measure real usage: Claude Code (Python hook reading the session's token usage after each tool call) and OpenCode V2 (plugin using the same figure OpenCode compacts on) warn the orchestrator at `handoff_at_percent` and re-point it to the state file after a compaction; Cursor only reports usage when it compacts, so its hook shows you a message then. All three tell a fresh session that a handoff is pending.

For low-level or custom orchestration you can invoke the `factory-coder`, `factory-reviewer`, and `factory-verifier` subagents directly (see [Supported tools](#-supported-tools)); prefer driving work through `factory-build` so gates and parallelism stay consistent.

### 📦 Stage 4: Ship

When every task is `done`, the skill opens one PR from `factory/<slug>` into your base branch with a completion summary. **Quality gate: merge the epic PR.**

### 🗄️ Archiving a project

When a feature has shipped, use the [`factory-archive`](.ai-factory/harnesses/claude/skills/factory-archive/SKILL.md) skill; more detail in [`reference.md`](.ai-factory/harnesses/claude/skills/factory-archive/reference.md).

**How to use it.** In your harness, ask the agent in plain language, for example: *Archive project `my-feature`*, *archive `oauth2`*, or *clean up the factory project for that slug*. The agent follows the skill: it confirms the slug, that the **Design Doc will move** into the archive, and that the `projects/<slug>` tree will be removed.

**What you get.** One self-contained run folder, **no duplicate `project-summary`**, and the slug directory under `projects/` is removed (you can start a new feature with the same slug later if needed).

| Location                                | After a successful archive                                                                                                                                                                                                                   |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.ai-factory/archive/<slug>/<timestamp>/` | `00-design.md` — moved from `projects/` (not edited), `project-summary.md` — single summary (epic, evaluation highlights, one section per task with review/verify), `dependency-graph.md` — full Mermaid + legend from `01-epic` when available |
| `.ai-factory/projects/<slug>/`            | **Removed** (empty after the move and cleanup)                                                                                                                                                                                               |

**What stays** elsewhere: all of `.ai-factory/` except that slug (config, templates, other slugs' folders). The factory's `.ai-factory/templates/` is never deleted.

**Git.** In this repository, `.ai-factory/projects/*` and `.ai-factory/archive/*` are **gitignored** (with `.gitkeep` placeholders) so local factory and archive output stay off the default commit unless you opt in.

## 📁 Project Structure

```
.ai-factory/
  harnesses/                       # Ready-to-copy agents and skills, one folder per harness
    claude/                        # Same layout in cursor/ and opencode/
      INSTALL.md                   # Harness-specific install steps and target paths
      agents/
        factory-architect.md
        factory-evaluator.md       # Design Doc red team
        factory-planner.md
        factory-coder.md
        factory-reviewer.md
        factory-verifier.md
      skills/                      # Core: packaged workflows, one per stage
        factory-design/SKILL.md    # Stage 1: Design Doc paths + Evaluator + quality gate
        factory-plan/SKILL.md      # Stage 2: Planner, epic + task DAG, quality gate
        factory-build/SKILL.md     # Stage 3: parallel tasks in worktrees, review/verify, PR per task
        factory-archive/           # Clean up a finished .ai-factory/projects slug
          SKILL.md
          reference.md
      hooks/factory_context.py     # Optional context handoff hooks (Claude Code; also in cursor/)
    cursor/
    opencode/
      plugins/factory-context/     # Optional context handoff plugin (OpenCode V2)
  config.md                        # Project-specific configuration
  templates/                       # Output format templates
    design.md                      # Design Doc template
    evaluation.md                  # Evaluator report template
    epic.md                        # Epic + Mermaid dependency graph
    task.md
    review.md
    verify.md
    build-state.md                 # factory-build handoff state
    ci/
      factory-checks.yml           # GitHub Actions: runs config.md checks on every PR
  projects/                        # Work in progress (gitignored)
    <slug>/
      00-design.md
      evaluations/
        00-design-evaluation.md    # Evaluator report (persisted by main agent)
      01-epic.md
      build-state.md               # Orchestrator state for resume / handoff
      tasks/
        T001-<slug>.md
      reviews/
        T001-review.md             # Reviewer report (persisted by main agent)
      verifications/
        T001-verify.md             # Verifier report (persisted by main agent)
  archive/                         # Self-contained archive runs (gitignored)
    <slug>/
      <timestamp>/
        00-design.md               # Moved from projects/<slug>/
        dependency-graph.md        # Mermaid + legend (from 01-epic)
        project-summary.md         # Single summary; links to ./00-design and ./dependency-graph
  examples/                        # Example artifacts for reference
    oauth2/
      00-design.md
      evaluations/
        00-design-evaluation.md    # Example evaluation
      tasks/
        T001-add-oauth-providers.md
install-factory-instructions.md    # Entry point your AI agent follows to install
.github/scripts/check-harnesses.sh # CI: harness copies stay in sync
```

## 🔍 Important Implementation Details

### Two Entry Paths

The factory supports two starting points:

**Path A** — No Design Doc exists. The Architect generates one from requirements, then the Evaluator critiques it. This is the full agent-driven path.

**Path B** — A Design Doc already exists (written by a human, by another tool, or from a previous session). Skip directly to the Evaluator.

Both paths converge at the Evaluator. No Design Doc reaches the Planner without being stress-tested. This prevents garbage-in-garbage-out — whether the Design Doc came from the Architect, a human, or ChatGPT, it gets the same adversarial review.

### Task Status Lifecycle

```
draft → in-progress → implemented → in-review → done
            │   ↑          │            │
            │   │  review/verify failed │ you request changes
            │   └── feedback appended ──┘ on the PR
            │       Coder re-invoked
            ▼
         blocked  (Coder blocker, or max_iterations reached)
```

- `draft` — Task created by Planner, waiting for its prerequisites to be `done`
- `in-progress` — Its branch and worktree exist and the Coder is working on it
- `implemented` — Coder finished, awaiting review + verification
- `in-review` — Review + verification passed; its PR into the epic branch is open
- `done` — You merged its PR
- `blocked` — Coder found a contradiction or impossible scenario, or the task hit `max_iterations`; the task file has an escalation summary

### The Coder-Reviewer-Verifier Loop

The core quality enforcement mechanism is the parallel fork-join loop, the factory's inspection station. Every running task has its own loop in its own worktree:

```
Coder implements
      │
  ┌───┴───┐          ← fork: both run in parallel
  ▼       ▼
Reviewer  Verifier    ← different concerns, different models
  │       │
  └───┬───┘          ← join: both must pass
      │
  both pass ──▶ PR into epic branch ──▶ you merge ──▶ Done
  any fail  ──▶ feedback to Coder ──▶ loop (max_iterations, then blocked)
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

### 🚦 Human Quality Gates

Four mandatory human checkpoints in every run:

1. **Design Doc Evaluation** — Review the Evaluator's critique and decide whether the Design Doc is ready for planning
2. **Task Plan Approval** — Review the task decomposition for scope and ordering
3. **Task Sign-off** — Review the task PR (with the review report, verification results and CI) and merge it into the epic branch
4. **Final Merge** — Review the epic PR with the complete feature and merge it into your base branch

Use the `factory-design`, `factory-plan`, and `factory-build` skills so the orchestrator follows the stages, parallel review/verify, and these gates explicitly — skills replace a separate always-on workflow rule.

## 🧰 Supported tools

soloAIfactory supports **Claude Code**, **Cursor** and **OpenCode**. Each harness has its own folder in `.ai-factory/harnesses/` with agents and skills already in the format that harness expects, so installing is a plain copy. Templates and `config.md` are shared.

| | Claude Code | Cursor | OpenCode |
|---|---|---|---|
| Agents (project) | `.claude/agents/` | `.cursor/agents/` | `.opencode/agents/` |
| Skills (project) | `.claude/skills/` | `.cursor/skills/` | `.opencode/skills/` |
| Agents (user) | `~/.claude/agents/` | `~/.cursor/agents/` | `~/.config/opencode/agents/` |
| Skills (user) | `~/.claude/skills/` | `~/.cursor/skills/` | `~/.config/opencode/skills/` |
| Read-only agents | `tools: Read, Grep, Glob` allowlist; `+ Bash` for Reviewer and Verifier | `readonly: true` | `permissions` denying `edit`; Evaluator also denies `shell` |
| Default models | Architect, Evaluator: `opus`; Planner, Coder, Reviewer: `sonnet`; Verifier: `haiku` | Architect, Evaluator, Planner: `grok-4.7`; Coder, Reviewer, Verifier: `composer-2.5` | none (`model` omitted, inherits the session's model) |
| Invoking a subagent | Agent tool with `subagent_type: factory-coder` | Delegate by name, e.g. `/factory-coder <task path>` | `subagent` tool with `factory-coder` |

Skills follow the [Agent Skills](https://agentskills.io) standard (`name` matching the folder, plus `description`). The only per-harness difference inside a skill is its `## Invoking subagents` section.

Read-only agents (Evaluator, Reviewer, Verifier) never write files: they return their report and the orchestrating skill persists it. The Evaluator has no shell at all, so it is hard read-only. The Reviewer (`git diff`) and Verifier (test/lint/build commands) need a shell, which can still write files, so for them read-only also relies on the prompt.

### Choosing models

Each agent ships with a default model per harness (see the table above; the source of truth is the `model` line in each shipped agent file). The installer shows each agent's model and lets you keep or change it, then writes your choice into the installed agent's `model` line. To change one later, edit that line in the installed file, for example `.claude/agents/factory-verifier.md`. A reinstall keeps your current models unless you pick new ones. Each harness's `INSTALL.md` lists its accepted model formats.

### Keeping harness copies in sync

Agent prompts and skill content are duplicated across harness folders on purpose, so each folder is complete and installs by copying. When you change a prompt or skill, make the same change in every harness folder. CI (`.github/workflows/harness-check.yml`) runs `.github/scripts/check-harnesses.sh` on every pull request and fails when:

- a harness is missing an agent or skill file that another has,
- an agent's prompt (everything below the frontmatter) differs between harnesses,
- a skill differs between harnesses outside its `## Invoking subagents` section, or
- a skill's `name` does not match its folder, an agent's `name` (where the harness uses one) does not match its filename, or a skill or agent has no `description`.

### Project-level vs user-level

- **Project-level** (default): the agents and skills live in the repo's harness folder (e.g. `.claude/`). Commit them so everyone gets the same setup.
- **User-level**: installed under your home directory, so every repo on the machine gets them. Each project still needs `.ai-factory/config.md` and `.ai-factory/templates/`, which the installer copies.

Cursor also reads `.claude/agents/` and `.claude/skills/`, and OpenCode also reads `.claude/skills/`. If you install more than one harness in the same repo, each harness's own folder wins for agents; Cursor may list duplicate skills.

### Adding a harness

Add `.ai-factory/harnesses/<name>/` with an `INSTALL.md` (target paths, steps, verification) and the same `agents/` and `skills/` files as the other harnesses, in that harness's format. Then add a row to the table in `install-factory-instructions.md`.

## 🎛️ Customizing for Your Project

### Stack Configuration

Edit `.ai-factory/config.md` — the Verifier reads test/lint/build commands from here, and the Coder reads conventions.

### Agent Prompts

Each agent in `.ai-factory/harnesses/<harness>/agents/` is a plain Markdown file. Edit them (the same change in every harness folder, then reinstall) to:

- Add project-specific rules to the Coder (e.g., "always use repository pattern")
- Adjust Reviewer severity thresholds
- Add domain-specific checklists to the Architect
- Tweak the Evaluator's adversarial tone or focus areas

### Templates

Templates in `.ai-factory/templates/` define the output format. Modify them to:

- Add sections specific to your domain (e.g., compliance, accessibility)
- Change the review severity levels
- Add required fields to the Design Doc
- Adjust the Evaluator's output structure

### Adding New Agents

Add the new agent as `factory-<name>.md` in every harness's `agents/` folder, using that harness's frontmatter (see [Supported tools](#-supported-tools)) and the same prompt body. New skills go in `skills/<skill-name>/SKILL.md` in every harness (the frontmatter `name` must match the folder name). Reinstall so each tool picks them up; each tool delegates based on the description.

## 📚 File Reference

### `.ai-factory/templates/task.md` — The Most Critical File

The task template is the linchpin of the factory. A well-written task:

- States a one-sentence business **Objective**
- Uses **Acceptance Criteria** (Gherkin scenarios) as the primary spec — mappable directly to tests
- Keeps technical detail in optional **Dev Notes** (paths, snippets, constraints, dependency interfaces)
- Lists dependencies briefly without front-loading implementation detail

The `examples/oauth2/tasks/T001-add-oauth-providers.md` file demonstrates a fully populated task.

### `.ai-factory/templates/design.md` — The Design Doc

The Architect fills this template to produce `00-design.md`: metadata, problem statement, goals and non-goals, architecture overview, data model and API surface changes, a file impact map, risks and mitigations, open questions, and an approval checklist. Bring-your-own Design Docs should follow the same structure.

### `.ai-factory/templates/epic.md` — Epic and Mermaid dependency graph

The Planner uses this for `01-epic.md`: task list, a fenced Mermaid diagram of the full DAG (edge direction: prerequisite → dependent), optional `classDef` colors per parallel stream with a neutral style for merge tasks, and a legend.

### `.ai-factory/templates/evaluation.md` — The Evaluator's Output Format

The evaluation template structures the Evaluator's critique into: Alignment Check, Executive Summary, Critical Vulnerabilities & Blind Spots, Trade-off Analysis, Alternative Approaches, Hard Questions, and a Verdict.

The `examples/oauth2/evaluations/00-design-evaluation.md` file demonstrates a full evaluation showing how the Evaluator critiques a real Design Doc.

### `.ai-factory/config.md` — Project Configuration

The Verifier reads command configurations from here. If a command is missing or set to `none`, that check is skipped. At minimum, `test_command` and `lint_command` should be set. The `## Build` section sets `max_concurrent_tasks`, `max_iterations`, `worktree_dir`, `base_branch`, `handoff_after_rounds` and `handoff_at_percent` for the build stage. If you installed `factory-checks.yml`, keep its commands in sync with this file.

### `.ai-factory/templates/ci/factory-checks.yml` — CI check

A GitHub Actions workflow template that runs the `config.md` Install, Test, Lint, Type check and Build commands on every pull request, so CI reproduces the Verifier's result on each task PR. The installer offers to copy it to `.github/workflows/` and fill it in.

### `.ai-factory/harnesses/<harness>/skills/` — Workflow (stages and gates)

The factory's procedure (paths, Evaluator, Planner, build loop, human quality gates) lives in the `factory-design`, `factory-plan`, `factory-build`, and `factory-archive` skills. Invoke or follow those skills instead of a separate always-on workflow rule.

## ✅ Requirements

- [Claude Code](https://claude.com/claude-code), [Cursor](https://cursor.com) with agent mode, or [OpenCode](https://opencode.ai)
- A project with a configured test runner and linter
- A git repository with a remote you can push to, and a way for the agent to open pull requests (for example the [`gh`](https://cli.github.com) CLI)
- No other dependencies — this is pure configuration

## 🩺 Troubleshooting

For a clean reinstall, ask your agent to follow [`install-factory-instructions.md`](install-factory-instructions.md) again. It replaces only `factory-*` agents and skills (asking first about any you changed), leaves your own agents and skills alone, never overwrites `.ai-factory/config.md` or `.ai-factory/projects/`, and offers to update templates that differ from the factory copy.

If the agents or skills don't show up after installing, restart the harness; most only scan their folders at startup.

## 🙏 Acknowledgments

Built on [Agent Skills](https://agentskills.io) and subagents in [Claude Code](https://code.claude.com/docs/en/sub-agents), [Cursor](https://cursor.com/docs/subagents) and [OpenCode](https://opencode.ai/docs/agents/), using the orchestrator pattern with context isolation.
