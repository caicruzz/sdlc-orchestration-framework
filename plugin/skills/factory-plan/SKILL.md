---
name: factory-plan
description: >-
  Stage 2 (Plan) — decompose an approved Design Doc into self-contained Gherkin tasks and
  an epic with Mermaid task DAG via factory-planner. Preconditions: evaluated Design Doc,
  human approved for planning. Use for planning stage, 01-epic, task breakdown,
  or "decompose Design Doc into tasks".
---

# Stage 2 (Plan) — Planner

**Stage 2** — Turn an **already approved** Design Doc into **`.ai-factory/projects/<slug>/01-epic.md`** and **`tasks/T<id>-<suffix>.md`**. Stop at the **human approval gate** for the task plan. Do **not** invoke the Coder, Reviewer, or Verifier here.

## When to use

- The Design Doc at **`.ai-factory/projects/<slug>/00-design.md`** exists, has passed evaluation, and **the human has approved proceeding** beyond Stage 1
- User asks for *tasks*, *epic*, *dependency graph*, *Gherkin tasks*, or *plan the feature*

## Preconditions

1. **`<slug>`** resolved — project directory **`.ai-factory/projects/<slug>/`**
2. **`00-design.md`** is present and is the **approved** design to plan from
3. **`.ai-factory/config.md`** is available for agents that need it. If **`.ai-factory/config.md`** is missing, **offer to run `factory-setup` first** and continue only after it exists (or the user explicitly declines)
4. If Stage 1 was skipped out-of-band (e.g. importing a project): ensure **Evaluator** ran and human **explicitly OKs planning** anyway — Stage 3 expects an honest plan from a validated Design Doc

## Templates

Templates are in `templates/` next to this SKILL.md. Paste the template's full content into the subagent prompt under a `Template` heading. The Planner never reads these files itself — files present on disk are not automatically attached to subagent runs, and the installed skill directory may be outside the workspace.

## Procedure

1. **Read** **`templates/epic.md`** and **`templates/task.md`** next to this SKILL.md.
2. **Invoke the `factory-planner` subagent** with a prompt that contains:
   - the path to the **approved** Design Doc, e.g. **`.ai-factory/projects/<slug>/00-design.md`** (verbatim path)
   - the full content of **both** **`templates/epic.md`** and **`templates/task.md`**, pasted under a **`Template`** heading (the Planner stops if its prompt has no `Template` section)
3. The Planner **reads the Design Doc only** and produces:
   - **`01-epic.md`** at **`.ai-factory/projects/<slug>/01-epic.md`**, following the pasted epic template
   - **`tasks/T<id>-<slug-or-name>.md`** under **`.ai-factory/projects/<slug>/tasks/`**, one file per task, following the pasted task template

### Epic and graph (required shape)

The epic **must** include **`## Task dependency graph`** with a valid fenced **`mermaid`** **flowchart** covering **every** task:

- **`flowchart TD`** or **`flowchart LR`**. One node per task; IDs **`T001`**, **`T002`**, … match task filenames
- **`T001 --> T002`** means **T002 depends on T001** (T001 finishes before T002)
- **Parallel streams**: when meaningful, **color-code** streams with **`classDef`** / **`class`**; **merge/join** tasks use a **neutral** style (e.g. gray)
- **Legend**: short bullets under the diagram mapping streams (and merge style when used) **unless** there is only a linear chain — then **one** node style suffices
- **Self-contained tasks** — Each task embeds requirements and behavior the **Coder** needs; **orchestration** does not pass the Design Doc, epic, or other tasks into the Coder prompt—only **one task file** plus **`.ai-factory/config.md`** (the Coder may still use the full repository)

### Gherkin and task quality

- Each task carries **Given/When/Then** scenarios the Coder maps to tests
- Dependencies and interfaces between tasks are explicit in the task body

4. **Human quality gate — required:** **Wait for explicit human approval** of the task plan (epic + tasks + graph) before any **Stage 3** implementation work

5. **Stop** this skill. Next step: **[`factory-build`](../factory-build/SKILL.md)** — tasks in **dependency order** (Coder → parallel Review + Verify).

## What you must not do in Stage 2

| Do not | Why |
|--------|-----|
| Invoke **Coder**, **Reviewer**, or **Verifier** | Stage 3 — after plan approval |
| Plan from a **non-approved** or **missing** Design Doc | Plan must match agreed design |
| Give the **Coder** the Design Doc or full epic in this skill | Stage 3 passes one task + config only; Planner must embed spec context in each task |
| Omit **`## Task dependency graph`** or **Mermaid** that matches all tasks | Required for ordering and parallel work |

## Invoking subagents
Wherever this skill says *invoke the `factory-<name>` subagent*:
- **Cursor**: delegate by name, e.g. `/factory-<name> <input>`.
- **Claude Code**: call the Agent tool with `subagent_type: factory-<name>`.
The installed agents live in `~/.claude/agents/`; a project `.claude/agents/factory-<name>.md`
overrides one by each tool's own precedence. Pass only the inputs this skill names
(paths, task IDs, inlined template content).

## Quick reference

| Output | Path |
|--------|------|
| Epic + graph | `.ai-factory/projects/<slug>/01-epic.md` |
| Task files | `.ai-factory/projects/<slug>/tasks/T<id>-<suffix>.md` |
| Design Doc (read-only input) | `.ai-factory/projects/<slug>/00-design.md` |
| Epic template | `templates/epic.md` (next to this SKILL.md) |
| Task template | `templates/task.md` (next to this SKILL.md) |

**Next stage:** **`factory-build`** — Coder, then parallel Reviewer + Verifier, per task following the epic graph.

## Verification (for the agent)

- **`01-epic.md`** exists and includes **`## Task dependency graph`** with Mermaid covering all listed tasks
- **`tasks/`** contains **`.md`** files per task referenced in the epic; IDs line up with the graph
- **Human** has been prompted to **approve the plan** before treating Stage 2 as complete
