---
name: sdlc-tdd
description: >-
  SDLC Phase 1 — produce or place a TDD, run the Evaluator, persist evaluation,
  and stop at the human approval gate. Path A: no TDD yet — invoke
  sdlc-architect. Path B: TDD already exists at .sdlc/projects/<slug>/00-tdd.md.
  Use for design phase, TDD workflow, 00-tdd, architectural design before
  planning, or "evaluate the TDD".
---

# SDLC Phase 1 — TDD (Architect + Evaluator)

**Phase 1: Design** — produce or place a TDD, run the Evaluator, persist the evaluation, and stop at the **human approval gate** for the TDD. Do **not** invoke the Planner or start implementation in this skill.

## When to use

- Starting a new feature and need a **Technical Design Document** at **`.sdlc/projects/<slug>/00-tdd.md`**
- A TDD **already exists** (human-written or imported) and you need **evaluation** before planning
- The user says: *TDD phase*, *design document*, *evaluate 00-tdd*, *red-team the TDD*, *Path A* / *Path B* for SDLC design

## Preconditions

1. **Resolve `<slug>`** with the user if unclear — kebab-case folder name under **`.sdlc/projects/<slug>/`**
2. Ensure **`.sdlc/config.md`** (or project config) is available to agents that need it; the Architect references project conventions
3. TDDs use the template at **`.sdlc/templates/tdd.md`**

## Path A — No TDD exists

1. **Invoke `/sdlc-architect`** with the feature request, requirements, or a path to a requirements document.
2. The Architect explores the codebase and writes a TDD to **`.sdlc/projects/<slug>/00-tdd.md`**.

## Path B — TDD already exists

1. **Place** (or **reference**) the TDD at **`.sdlc/projects/<slug>/00-tdd.md`**
   - If the user’s document lives elsewhere, copy or consolidate into that path so planning has a single canonical TDD
2. **Do not** run the Architect to regenerate the TDD unless the user explicitly asks to **replace** or **refresh** it

## Both paths — Evaluator (mandatory)

**Never skip the Evaluator** for any TDD, whether from Path A, Path B, or a revision loop.

1. **Invoke `/sdlc-evaluator`** with the TDD path: **`.sdlc/projects/<slug>/00-tdd.md`**
2. The Evaluator **critically** examines the TDD (flaws, blind spots, trade-offs, gaps) and returns a **structured evaluation** with a **verdict**
3. **Persist** the full evaluation: write it to **`.sdlc/projects/<slug>/evaluations/00-tdd-evaluation.md`**
   - The Evaluator is **readonly** — it only returns text; the **main agent** (or this workflow) is responsible for saving that text to the file
4. **If the verdict** is `needs-revision` or `blocked`:
   - Present the evaluation to the human clearly
   - **Wait** for the human to revise the TDD (or direct changes)
   - **Re-invoke** `/sdlc-evaluator` on the **revised** TDD
   - Append or update **`.sdlc/projects/<slug>/evaluations/00-tdd-evaluation.md`** to reflect the latest run (or successive timestamped evaluation files per team convention; default is one `00-tdd-evaluation.md` for the latest run)
5. **Human gate — required:** After the evaluation verdict allows progress (i.e. not `needs-revision` / `blocked` for the current revision), **wait for explicit human approval** of the TDD before any Phase 2 (Planner) work
6. **Stop** this skill. Next step: use the **`sdlc-plan`** skill and **`/sdlc-planner`** only **after** human approval of the TDD.

## What you must not do in Phase 1

| Do not | Why |
|--------|-----|
| Invoke **Planner** or create **tasks/** / **01-epic.md** | Phase 2 — requires approved TDD first |
| **Skip** the Evaluator | Every TDD must pass through the Evaluator in Phase 1 |
| **Share** the TDD with a **Coder** in this phase | Implementation is Phase 3 from task files, not the TDD |
| Let the **Evaluator** write files on disk | Readonly; main agent persists evaluation |

## Subagents (optional for the user)

The **primary** path is: follow this skill’s steps, using **`/sdlc-architect`** and **`/sdlc-evaluator`** as specified. The same agents can be run manually; behavior must match this procedure.

## Quick reference

| Path | `00-tdd.md` | Architect | Evaluator |
|------|-------------|-----------|-----------|
| **A** | Created by agent | Yes (`/sdlc-architect`) | Mandatory |
| **B** | Placed or consolidated by you | No unless replacing | Mandatory |

| Artifact | Path |
|----------|------|
| TDD | `.sdlc/projects/<slug>/00-tdd.md` |
| Persisted evaluation | `.sdlc/projects/<slug>/evaluations/00-tdd-evaluation.md` |
| TDD template | `.sdlc/templates/tdd.md` |

**Next phase:** after human approval → **[`sdlc-plan`](../sdlc-plan/SKILL.md)** — **`/sdlc-planner`**

## Verification (for the agent)

- **Path A:** **`.sdlc/projects/<slug>/00-tdd.md`** exists after Architect
- **Path B:** same path exists before Evaluator
- **`.sdlc/projects/<slug>/evaluations/00-tdd-evaluation.md`** exists and matches the latest Evaluator output
- **Human** has been prompted for **approval** after a passing eval loop; do not claim Phase 1 “done” without that gate
