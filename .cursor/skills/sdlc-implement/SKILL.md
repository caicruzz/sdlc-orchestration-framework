---
name: sdlc-implement
description: >-
  SDLC Phase 3 — per-task loop: implement with sdlc-coder, then run sdlc-reviewer
  and sdlc-verifier in parallel, reconcile failures, human sign-off, mark done.
  Respect task DAG from 01-epic. Use for Implement T001, coding phase, CR loop,
  review verify loop.
---

# SDLC Phase 3 — Implementation (Coder → parallel Review + Verify → loop)

**Phase 3** — For **each** task, in **dependency order** from **`01-epic.md`**, run: **Coder** → **Reviewer** and **Verifier** **in parallel** → handle outcomes → **human approval** → mark task **done**. Repeat until all tasks for the slug are complete. This skill does **not** replace **`.sdlc/config.md`** for the Verifier or the **one-task-only** contract for the Coder.

## When to use

- **`.sdlc/projects/<slug>/01-epic.md`** and **`tasks/T<id>-*.md`** exist and the **task plan is human-approved**
- User says *implement T001*, *run the CR loop*, *code this task*, *review and verify*

## Preconditions

1. **`<slug>`** resolved — **`.sdlc/projects/<slug>/`**
2. **`01-epic.md`** and the **task dependency graph** define **order** — do not start a task until its **prerequisites** are **done** (per epic + graph: `T001 --> T002` means T001 before T002)
3. **`.sdlc/config.md`** present — **Verifier** uses **config only**, not task text (see isolation below)

## Context isolation (strict)

| Role | Reads | Must not receive |
|------|--------|------------------|
| **Coder** | **One** task file **path** + **`.sdlc/config.md`** (per agent definition) | TDD, epic, other tasks |
| **Reviewer** | One task file + relevant code diff | Editing code *(Reviewer is read-only)* |
| **Verifier** | **`.sdlc/config.md`** — task identity as **task ID** (e.g. `T001`) for scope | Full task prose / feature context |

## Loop (one task iteration)

Treat **Steps A → B → C → D** as one cycle for the **current** task file.

### Step A — Implement

1. **Invoke `/sdlc-coder`** with the task file path, e.g. **`.sdlc/projects/<slug>/tasks/T001-<name>.md`**
2. The Coder implements from the task **Gherkin** and updates task status toward **`implemented`** as defined in your task template
3. **Coder autonomy:** Implementation choices and whether to chase optional Reviewer nits stay with the Coder — **every** specified **Gherkin** scenario **must** still pass

### Step B — Review and Verify (**parallel** — do not sequentialize)

**Launch together (same orchestration round):**

- **`/sdlc-reviewer`** with the **same** task file path
- **`/sdlc-verifier`** with the **task ID** only (e.g. **`Verify T001`**) — **not** the task markdown body

**Never skip** this parallel pair for a implemented task headed for sign-off.

### Step C — Reconcile outcomes

| Reviewer verdict | Verifier verdict | Action |
|------------------|------------------|--------|
| pass | pass | Proceed to Step D |
| **revisions-needed** | anything | **Append** feedback to the task file (**do not** delete earlier feedback blobs), return to Step A |
| anything | **fail** | **Append** Verifier output to the task file, return to Step A |
| Mixed failure | Mixed failure | Append **both**, return to Step A |

Re-invoke **Coder** with the **same** task file path **after** appends.

### Step D — Human sign-off

1. Present **Reviewer** + **Verifier** summaries for this task clearly
2. **Wait for explicit human approval** — do **not** mark **`done`** on the mere basis of automated pass unless your team defines that explicitly; the framework assumes a **human gate**
3. Set task status to **`done`** in the task file (per template conventions)

Then **advance** to the **next ready** task whose dependencies are all **`done`** (use **`01-epic.md`** + graph).

### All tasks finished (Phase 4 hook)

When **every** planned task for the slug is **`done`**, give the human a short **completion summary** and offer final review / merge paths as appropriate. Optionally use **archive** when the feature is retired — see **`sdlc-archive`**.

## What you must not do in Phase 3

| Do not | Why |
|--------|-----|
| Run Reviewer and Verifier **sequentially** or **omit one** before sign-off | **Parallel** Review + Verify is required |
| Paste **task text** into the **Verifier** | **config.md** (+ task ID) only |
| Put **TDD** or **epic** into **Coder** context | Violates Planner contract |
| **Remove** previous failure feedback when re-invoking Coder | **Append** only |
| **Let Reviewer edit** implementation | **Coder** edits; Reviewer reads |
| Implement tasks **out of DAG order** unless the user overrides with scope | Depends-on edges are binding |

## Subagents (optional for the user)

Same agents with explicit slashes — equivalent if inputs match:

```text
/sdlc-coder Implement .sdlc/projects/<slug>/tasks/T001-<name>.md
/sdlc-reviewer Review .sdlc/projects/<slug>/tasks/T001-<name>.md
/sdlc-verifier Verify T001
```

## Quick reference

| Item | Value |
|------|--------|
| Task files | `.sdlc/projects/<slug>/tasks/T<id>-*.md` |
| Order | From **`01-epic.md`** **Task dependency graph** |
| Parallel step | **`/sdlc-reviewer`** (task path) **+** **`/sdlc-verifier`** (task ID) |

**Previous phase:** approved plan (**`sdlc-plan`**).

## Verification (for the agent)

- **Coder** invoked with **exact** task path; **Reviewer + Verifier** launched **in parallel** after implementation for that iteration
- On failure, task file shows **appended** feedback, then Coder **re-invoked**
- Human **explicitly acknowledged** completion before moving task to **`done`** or starting the next task if your process bundles approval per task
