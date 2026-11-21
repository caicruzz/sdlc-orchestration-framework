---
name: factory-design
description: >-
  Stage 1 (Design) — produce or place a Design Doc, run the Evaluator, persist evaluation,
  and stop at the human approval gate. Path A: no Design Doc yet — invoke
  factory-architect. Path B: Design Doc already exists at .ai-factory/state/projects/<slug>/00-design.md.
  Use for design stage, Design Doc workflow, 00-design, architectural design before
  planning, or "evaluate the Design Doc".
---

# Stage 1 (Design) — Architect + Evaluator

**Stage 1: Design** — produce or place a Design Doc, run the Evaluator, persist the evaluation, and stop at the **human approval gate** for the Design Doc. Do **not** invoke the Planner or start implementation in this skill.

## When to use

- Starting a new feature and need a **Design Doc** at **`.ai-factory/state/projects/<slug>/00-design.md`**
- A Design Doc **already exists** (human-written or imported) and you need **evaluation** before planning
- The user says: *Design Doc stage*, *design document*, *evaluate 00-design*, *red-team the Design Doc*, *Path A* / *Path B* for the design stage

## Preconditions

1. **Open the state** (see [State branch](#state-branch))
2. **Resolve `<slug>`** with the user if unclear — kebab-case folder name under **`.ai-factory/state/projects/<slug>/`**
3. Ensure **`.ai-factory/config.md`** (or project config) is available to agents that need it; the Architect references project conventions
4. Design Docs use the template at **`.ai-factory/templates/design.md`**

## State branch

Everything the factory writes about a feature lives under **`.ai-factory/state/`**: work in progress in **`projects/<slug>/`** (Design Doc, evaluations, epic, task files, reports, **`build-state.md`**) and finished runs in **`archive/<slug>/<ts>/`**. That folder is a git worktree of the **state branch**, so it survives fresh clones, cloud sessions and other machines. **`config.md`** → **`## State`** → **`state_branch`** names the branch (default **`factory-state`**). If it is **`none`**, `.ai-factory/state/` is a plain folder and you skip the rest of this section: state stays on this machine only. The main checkout must gitignore **`.ai-factory/state/`**.

**Open the state** before you read or write anything under `.ai-factory/state/`:

1. If `.ai-factory/state/.git` exists, the worktree is already there. **Sync it**: run `git -C .ai-factory/state pull --rebase --autostash origin <state_branch>`. If the remote has no `<state_branch>` yet, run `git -C .ai-factory/state push -u origin <state_branch>` instead. Then stop here
2. If `.ai-factory/state/` exists and is not empty, or the old folders `.ai-factory/projects/` or `.ai-factory/archive/` hold files, this is state from before the state branch. Ask the human before migrating it: move `.ai-factory/state/` (if present) to `.ai-factory/state.local-backup/`, run step 3, copy the old content into `.ai-factory/state/projects/` and `.ai-factory/state/archive/` (if a slug exists on both sides, ask which to keep), **save the state**, and tell the human which old folders they can delete
3. Otherwise run `git fetch origin <state_branch>:refs/remotes/origin/<state_branch>` (the explicit refspec also works in single-branch clones, which cloud agents often use), then:
   - If a local `<state_branch>` branch exists: `git worktree add .ai-factory/state <state_branch>`, then **sync it** as in step 1
   - Else, if the fetch worked: `git worktree add .ai-factory/state -b <state_branch> origin/<state_branch>`
   - Else, create the branch with no files, check it out and push it:

     ```bash
     empty_tree=$(git hash-object -t tree /dev/null)
     git branch <state_branch> "$(git commit-tree "$empty_tree" -m 'factory: start state branch')"
     git worktree add .ai-factory/state <state_branch>
     git -C .ai-factory/state push -u origin <state_branch>
     ```

**Save the state** at each checkpoint this skill names:

```bash
git -C .ai-factory/state add -A
git -C .ai-factory/state commit -m "factory(<slug>): <checkpoint>"   # skip when there is nothing to commit
git -C .ai-factory/state push -u origin <state_branch>
```

If the push is rejected, run `git -C .ai-factory/state pull --rebase --autostash origin <state_branch>` and push again. If the rebase or the autostash conflicts, stop and ask the human. If you cannot push at all (no remote, or no permission), tell the human the state is saved only on this machine and carry on. **Never** force-push the state branch or merge it into another branch.

## Path A — No Design Doc exists

1. **Invoke the `factory-architect` subagent** with the feature request, requirements, or a path to a requirements document.
   - **Include** the path **`.ai-factory/templates/design.md`** explicitly in the invocation prompt so the Architect reads the template: **files present on disk are not automatically attached** to subagent runs.
2. The Architect reads **`design.md`**, preserves its structure verbatim in **`00-design.md`**, explores the codebase, and fills placeholders.
3. **Save the state**

## Path B — Design Doc already exists

1. **Place** (or **reference**) the Design Doc at **`.ai-factory/state/projects/<slug>/00-design.md`**
   - If the user’s document lives elsewhere, copy or consolidate into that path so planning has a single canonical Design Doc
   - Then **save the state**
2. **Do not** run the Architect to regenerate the Design Doc unless the user explicitly asks to **replace** or **refresh** it

## Both paths — Evaluator (mandatory)

**Never skip the Evaluator** for any Design Doc, whether from Path A, Path B, or a revision loop.

1. **Invoke the `factory-evaluator` subagent** with the Design Doc path: **`.ai-factory/state/projects/<slug>/00-design.md`**
2. The Evaluator **critically** examines the Design Doc (flaws, blind spots, trade-offs, gaps) and returns a **structured evaluation** with a **verdict**
3. **Persist** the full evaluation: write it to **`.ai-factory/state/projects/<slug>/evaluations/00-design-evaluation.md`**
   - The Evaluator is **readonly** — it only returns text; the **main agent** (or this workflow) is responsible for saving that text to the file
   - Then **save the state**. Do the same after every later evaluation run and every Design Doc revision
4. **If the verdict** is `needs-revision` or `blocked`:
   - Present the evaluation to the human clearly
   - **Wait** for the human to revise the Design Doc (or direct changes)
   - **Re-invoke** the `factory-evaluator` subagent on the **revised** Design Doc
   - Append or update **`.ai-factory/state/projects/<slug>/evaluations/00-design-evaluation.md`** to reflect the latest run (or successive timestamped evaluation files per team convention; default is one `00-design-evaluation.md` for the latest run)
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

Wherever this skill says *invoke the `factory-<name>` subagent*, call the Agent (Task) tool with `subagent_type: factory-<name>` and the input as the prompt.

Pass **only** the inputs this skill names (paths, task IDs) — subagents do not see this conversation. Users may also invoke the same subagents manually; behavior must match this procedure.

## Quick reference

| Path | `00-design.md` | Architect | Evaluator |
|------|-------------|-----------|-----------|
| **A** | Created by agent | Yes (`factory-architect`) | Mandatory |
| **B** | Placed or consolidated by you | No unless replacing | Mandatory |

| Artifact | Path |
|----------|------|
| Design Doc | `.ai-factory/state/projects/<slug>/00-design.md` |
| Persisted evaluation | `.ai-factory/state/projects/<slug>/evaluations/00-design-evaluation.md` |
| Design Doc template | `.ai-factory/templates/design.md` |

**Next stage:** after human approval → **[`factory-plan`](../factory-plan/SKILL.md)** — **`factory-planner`**

## Verification (for the agent)

- **Path A:** **`.ai-factory/state/projects/<slug>/00-design.md`** exists after Architect
- **Path B:** same path exists before Evaluator
- **`.ai-factory/state/projects/<slug>/evaluations/00-design-evaluation.md`** exists and matches the latest Evaluator output
- **Human** has been prompted for **approval** after a passing eval loop; do not claim Stage 1 “done” without that gate
