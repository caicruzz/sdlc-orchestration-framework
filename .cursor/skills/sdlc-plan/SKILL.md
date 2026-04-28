---
name: sdlc-plan
description: >-
  SDLC Phase 2 — decompose an approved TDD into self-contained Gherkin tasks and
  an epic with Mermaid task DAG via sdlc-planner. Preconditions: evaluated TDD,
  human approved for planning. Use for planning phase, 01-epic, task breakdown,
  or "decompose TDD into tasks".
---

# SDLC Phase 2 — Planning (Planner)

**Phase 2** — Turn an **already approved** TDD into **`.sdlc/projects/<slug>/01-epic.md`** and **`tasks/T<id>-<suffix>.md`**. Stop at the **human approval gate** for the task plan. Do **not** invoke the Coder, Reviewer, or Verifier here.

## When to use

- The TDD at **`.sdlc/projects/<slug>/00-tdd.md`** exists, has passed evaluation, and **the human has approved proceeding** beyond Phase 1
- User asks for *tasks*, *epic*, *dependency graph*, *Gherkin tasks*, or *plan the feature*

## Preconditions

1. **`<slug>`** resolved — project directory **`.sdlc/projects/<slug>/`**
2. **`00-tdd.md`** is present and is the **approved** design to plan from
3. **`.sdlc/config.md`** is available for agents that need it
4. If Phase 1 was skipped out-of-band (e.g. importing a project): ensure **Evaluator** ran and human **explicitly OKs planning** anyway — Phase 3 expects an honest plan from a validated TDD

## Procedure

1. **Invoke `/sdlc-planner`** with the path to the **approved** TDD, e.g. **`.sdlc/projects/<slug>/00-tdd.md`** (verbatim path in the Planner invocation prompt)
2. The Planner **reads the TDD only** and produces:
   - **`01-epic.md`** at **`.sdlc/projects/<slug>/01-epic.md`**, following **`.sdlc/templates/epic.md`**
   - **`tasks/T<id>-<slug-or-name>.md`** under **`.sdlc/projects/<slug>/tasks/`**, one file per task, following **`.sdlc/templates/task.md`**

### Epic and graph (required shape)

The epic **must** include **`## Task dependency graph`** with a valid fenced **`mermaid`** **flowchart** covering **every** task:

- **`flowchart TD`** or **`flowchart LR`**. One node per task; IDs **`T001`**, **`T002`**, … match task filenames
- **`T001 --> T002`** means **T002 depends on T001** (T001 finishes before T002)
- **Parallel streams**: when meaningful, **color-code** streams with **`classDef`** / **`class`**; **merge/join** tasks use a **neutral** style (e.g. gray)
- **Legend**: short bullets under the diagram mapping streams (and merge style when used) **unless** there is only a linear chain — then **one** node style suffices
- **Self-contained tasks** — Each task embeds requirements and behavior the **Coder** needs; **orchestration** does not pass the TDD, epic, or other tasks into the Coder prompt—only **one task file** plus **`.sdlc/config.md`** (the Coder may still use the full repository)

### Gherkin and task quality

- Each task carries **Given/When/Then** scenarios the Coder maps to tests
- Dependencies and interfaces between tasks are explicit in the task body

3. **Human gate — required:** **Wait for explicit human approval** of the task plan (epic + tasks + graph) before any **Phase 3** implementation work

4. **Stop** this skill. Next step: **[`sdlc-implement`](../sdlc-implement/SKILL.md)** — tasks in **dependency order** (Coder → parallel Review + Verify).

## What you must not do in Phase 2

| Do not | Why |
|--------|-----|
| Invoke **Coder**, **Reviewer**, or **Verifier** | Phase 3 — after plan approval |
| Plan from a **non-approved** or **missing** TDD | Plan must match agreed design |
| Give the **Coder** the TDD or full epic in this skill | Phase 3 passes one task + config only; Planner must embed spec context in each task |
| Omit **`## Task dependency graph`** or **Mermaid** that matches all tasks | Required for ordering and parallel work |

## Subagents (optional for the user)

Primary path: **`/sdlc-planner`** as above. Users may run the Planner manually with the same inputs; behavior should match this procedure.

## Quick reference

| Output | Path |
|--------|------|
| Epic + graph | `.sdlc/projects/<slug>/01-epic.md` |
| Task files | `.sdlc/projects/<slug>/tasks/T<id>-<suffix>.md` |
| TDD (read-only input) | `.sdlc/projects/<slug>/00-tdd.md` |
| Epic template | `.sdlc/templates/epic.md` |
| Task template | `.sdlc/templates/task.md` |

**Next phase:** **`sdlc-implement`** — Coder, then parallel Reviewer + Verifier, per task following the epic graph.

## Verification (for the agent)

- **`01-epic.md`** exists and includes **`## Task dependency graph`** with Mermaid covering all listed tasks
- **`tasks/`** contains **`.md`** files per task referenced in the epic; IDs line up with the graph
- **Human** has been prompted to **approve the plan** before treating Phase 2 as complete
