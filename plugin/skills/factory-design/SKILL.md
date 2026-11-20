---
name: factory-design
description: >-
  Stage 1 (Design) — produce or place a Design Doc, run the Evaluator, persist evaluation,
  and stop at the human approval gate. Path A: no Design Doc yet — invoke
  factory-architect. Path B: Design Doc already exists at .ai-factory/projects/<slug>/00-design.md.
  Use for design stage, Design Doc workflow, 00-design, architectural design before
  planning, or "evaluate the Design Doc".
---

# Stage 1 (Design) — Architect + Evaluator

**Stage 1: Design** — produce or place a Design Doc, run the Evaluator, persist the evaluation, and stop at the **human approval gate** for the Design Doc. Do **not** invoke the Planner or start implementation in this skill.

## When to use

- Starting a new feature and need a **Design Doc** at **`.ai-factory/projects/<slug>/00-design.md`**
- A Design Doc **already exists** (human-written or imported) and you need **evaluation** before planning
- The user says: *Design Doc stage*, *design document*, *evaluate 00-design*, *red-team the Design Doc*, *Path A* / *Path B* for the design stage

## Preconditions

1. **Resolve `<slug>`** with the user if unclear — kebab-case folder name under **`.ai-factory/projects/<slug>/`**
2. Ensure **`.ai-factory/config.md`** is available to agents that need it; the Architect references project conventions. If **`.ai-factory/config.md`** is missing in the repo, **offer to run `factory-setup` first** and continue only after it exists (or the user explicitly declines)
3. Design Docs use the template at **`templates/design.md`** next to this SKILL.md

## Templates

Templates are in `templates/` next to this SKILL.md. Paste the template's full content into the subagent prompt under a `Template` heading. For the evaluation report (**`templates/evaluation.md`**), no subagent gets the template: shape the returned report with it when persisting. Subagents never read these files themselves — files present on disk are not automatically attached to subagent runs, and the installed skill directory may be outside the workspace.

## Path A — No Design Doc exists

1. **Read** **`templates/design.md`** next to this SKILL.md.
2. **Invoke the `factory-architect` subagent** with a prompt that contains:
   - the feature request, requirements, or a path to a requirements document
   - the output path **`.ai-factory/projects/<slug>/00-design.md`**
   - the full content of **`templates/design.md`**, pasted under a **`Template`** heading (the Architect stops if its prompt has no `Template` section)
3. The Architect preserves the pasted template's structure verbatim in **`00-design.md`**, explores the codebase, and fills placeholders.

## Path B — Design Doc already exists

1. **Place** (or **reference**) the Design Doc at **`.ai-factory/projects/<slug>/00-design.md`**
   - If the user’s document lives elsewhere, copy or consolidate into that path so planning has a single canonical Design Doc
2. **Do not** run the Architect to regenerate the Design Doc unless the user explicitly asks to **replace** or **refresh** it

## Both paths — Evaluator (mandatory)

**Never skip the Evaluator** for any Design Doc, whether from Path A, Path B, or a revision loop.

1. **Invoke the `factory-evaluator` subagent** with the Design Doc path: **`.ai-factory/projects/<slug>/00-design.md`**
   - The Evaluator prompt includes **no template** — only the Design Doc path
2. The Evaluator **critically** examines the Design Doc (flaws, blind spots, trade-offs, gaps) and returns a **structured evaluation** with a **verdict**
3. **Persist** the full evaluation: write it to **`.ai-factory/projects/<slug>/evaluations/00-design-evaluation.md`**
   - The Evaluator is **readonly** — it only returns text; the **main agent** (or this workflow) is responsible for saving that text to the file
   - Read **`templates/evaluation.md`** next to this SKILL.md and shape the returned report with it when persisting (keep the Evaluator's findings and verdict; fit them to the template's sections)
4. **If the verdict** is `needs-revision` or `blocked`:
   - Present the evaluation to the human clearly
   - **Wait** for the human to revise the Design Doc (or direct changes)
   - **Re-invoke** the `factory-evaluator` subagent on the **revised** Design Doc
   - Append or update **`.ai-factory/projects/<slug>/evaluations/00-design-evaluation.md`** to reflect the latest run (or successive timestamped evaluation files per team convention; default is one `00-design-evaluation.md` for the latest run)
5. **Human quality gate — required:** After the evaluation verdict allows progress (i.e. not `needs-revision` / `blocked` for the current revision), **wait for explicit human approval** of the Design Doc before any Stage 2 (Planner) work
6. **Stop** this skill. Next step: use the **`factory-plan`** skill and **`factory-planner`** only **after** human approval of the Design Doc.

## What you must not do in Stage 1

| Do not | Why |
|--------|-----|
| Invoke **Planner** or create **tasks/** / **01-epic.md** | Stage 2 — requires approved Design Doc first |
| **Skip** the Evaluator | Every Design Doc must pass through the Evaluator in Stage 1 |
| **Share** the Design Doc with a **Coder** in this stage | Implementation is Stage 3 from task files, not the Design Doc |
| Let the **Evaluator** write files on disk | Readonly; main agent persists evaluation |

## Invoking subagents
Wherever this skill says *invoke the `factory-<name>` subagent*:
- **Cursor**: delegate by name, e.g. `/factory-<name> <input>`.
- **Claude Code**: call the Agent tool with `subagent_type: factory-<name>`.
The installed agents live in `~/.claude/agents/`; a project `.claude/agents/factory-<name>.md`
overrides one by each tool's own precedence. Pass only the inputs this skill names
(paths, task IDs, inlined template content).

## Quick reference

| Path | `00-design.md` | Architect | Evaluator |
|------|-------------|-----------|-----------|
| **A** | Created by agent | Yes (`factory-architect`) | Mandatory |
| **B** | Placed or consolidated by you | No unless replacing | Mandatory |

| Artifact | Path |
|----------|------|
| Design Doc | `.ai-factory/projects/<slug>/00-design.md` |
| Persisted evaluation | `.ai-factory/projects/<slug>/evaluations/00-design-evaluation.md` |
| Design Doc template | `templates/design.md` (next to this SKILL.md) |
| Evaluation template | `templates/evaluation.md` (next to this SKILL.md) |

**Next stage:** after human approval → **[`factory-plan`](../factory-plan/SKILL.md)** — **`factory-planner`**

## Verification (for the agent)

- **Path A:** **`.ai-factory/projects/<slug>/00-design.md`** exists after Architect
- **Path B:** same path exists before Evaluator
- **`.ai-factory/projects/<slug>/evaluations/00-design-evaluation.md`** exists and matches the latest Evaluator output
- **Human** has been prompted for **approval** after a passing eval loop; do not claim Stage 1 “done” without that gate
