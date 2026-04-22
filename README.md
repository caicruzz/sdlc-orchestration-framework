# Agent Orchestration Framework

An agent-driven SDLC framework for [Cursor](https://cursor.com). Define features, decompose them into testable tasks, implement with autonomous agents, and enforce quality through parallel review and verification — all controlled by human gates.

## How It Works

```
Requirements ──▶ [Architect] ──▶ TDD
                                     │
                   [Planner] ← reads TDD only
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

| Agent | Role | Reads | Writes | Model |
|---|---|---|---|---|
| **Architect** | Produces Technical Design Document from requirements | Requirements + codebase exploration | TDD at `.sdlc/projects/<slug>/00-tdd.md` | inherit |
| **Planner** | Decomposes TDD into self-contained Gherkin-based tasks | TDD only | Tasks at `.sdlc/projects/<slug>/tasks/T<id>-*.md` | inherit |
| **Coder** | Implements task + writes tests from Gherkin scenarios | ONE task + config | Production code + tests | inherit |
| **Reviewer** | Reviews code quality, bugs, scenario coverage | ONE task + code diff | Review report | inherit |
| **Verifier** | Runs tests, lint, typecheck, build mechanically | Config only | Verification report | fast |

### Context Isolation

Each agent operates with strict context boundaries:

- **Architect** → reads requirements and codebase, writes TDD
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

In Cursor's agent chat:

```
/sdlc-architect Create a TDD for adding OAuth2 login with Google and GitHub
```

## Workflow

### Phase 1: Design

```
> /sdlc-architect Create a TDD for <feature description>
```

The Architect explores your codebase and writes a Technical Design Document to `.sdlc/projects/<slug>/00-tdd.md`.

**Human gate: Review and approve the TDD.**

### Phase 2: Planning

```
> /sdlc-planner Decompose the TDD at .sdlc/projects/<slug>/00-tdd.md into tasks
```

The Planner reads the TDD and creates self-contained tasks with Gherkin scenarios in `.sdlc/projects/<slug>/tasks/`.

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

## Project Structure

```
.cursor/
  agents/                          # Agent definitions
    sdlc-architect.md
    sdlc-planner.md
    sdlc-coder.md
    sdlc-reviewer.md
    sdlc-verifier.md
  rules/
    sdlc-workflow.mdc              # Workflow enforcement rules
.sdlc/
  config.md                        # Project-specific configuration
  templates/                       # Output format templates
    tdd.md
    task.md
    review.md
    verify.md
  projects/                        # Generated artifacts (gitignored)
    <slug>/
      00-tdd.md
      01-epic.md
      tasks/
        T001-<slug>.md
      reviews/
        T001-review.md
      verifications/
        T001-verify.md
  examples/                        # Example artifacts for reference
    oauth2/
      00-tdd.md
      tasks/
        T001-add-oauth-providers.md
```

## Important Implementation Details

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

Three mandatory human checkpoints in every workflow:

1. **TDD Approval** — Review `.sdlc/projects/<slug>/00-tdd.md` for architectural soundness
2. **Task Plan Approval** — Review the task decomposition for scope and ordering
3. **Task Sign-off** — Review the review report + verification results before marking done

The workflow rule in `.cursor/rules/sdlc-workflow.mdc` prevents the agent from proceeding past these gates without explicit human approval.

## Customizing for Your Project

### Stack Configuration

Edit `.sdlc/config.md` — the Verifier reads test/lint/build commands from here, and the Coder reads conventions.

### Agent Prompts

Each agent in `.cursor/agents/` is a plain Markdown file. Edit them to:

- Add project-specific rules to the Coder (e.g., "always use repository pattern")
- Adjust Reviewer severity thresholds
- Add domain-specific checklists to the Architect

### Templates

Templates in `.sdlc/templates/` define the output format. Modify them to:

- Add sections specific to your domain (e.g., compliance, accessibility)
- Change the review severity levels
- Add required fields to the TDD

### Adding New Agents

Create a new `.md` file in `.cursor/agents/`:

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

### `.sdlc/config.md` — Project Configuration

The Verifier reads command configurations from here. If a command is missing or set to `none`, that check is skipped. At minimum, `test_command` and `lint_command` should be set.

### `.cursor/rules/sdlc-workflow.mdc` — Workflow Enforcement

This Cursor rule file instructs the main Cursor agent on the SDLC process. It enforces:
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
