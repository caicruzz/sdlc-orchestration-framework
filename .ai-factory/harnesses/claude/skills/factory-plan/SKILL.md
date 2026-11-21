---
name: factory-plan
description: >-
  Stage 2 (Plan) — decompose an approved Design Doc into self-contained Gherkin tasks and
  an epic with Mermaid task DAG via factory-planner. Preconditions: evaluated Design Doc,
  human approved for planning. Use for planning stage, 01-epic, task breakdown,
  or "decompose Design Doc into tasks".
---

# Stage 2 (Plan) — Planner

**Stage 2** — Turn an **already approved** Design Doc into **`.ai-factory/state/projects/<slug>/01-epic.md`** and **`tasks/T<id>-<suffix>.md`**. Stop at the **human approval gate** for the task plan. Do **not** invoke the Coder, Reviewer, or Verifier here.

## When to use

- The Design Doc at **`.ai-factory/state/projects/<slug>/00-design.md`** exists, has passed evaluation, and **the human has approved proceeding** beyond Stage 1
- User asks for *tasks*, *epic*, *dependency graph*, *Gherkin tasks*, or *plan the feature*

## Preconditions

1. **Open the state** (see [State branch](#state-branch))
2. **`<slug>`** resolved — project directory **`.ai-factory/state/projects/<slug>/`**
3. **`00-design.md`** is present and is the **approved** design to plan from
4. **`.ai-factory/config.md`** is available for agents that need it
5. If Stage 1 was skipped out-of-band (e.g. importing a project): ensure **Evaluator** ran and human **explicitly OKs planning** anyway — Stage 3 expects an honest plan from a validated Design Doc

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

## Procedure

1. **Invoke the `factory-planner` subagent** with the path to the **approved** Design Doc, e.g. **`.ai-factory/state/projects/<slug>/00-design.md`** (verbatim path in the Planner invocation prompt)
2. The Planner **reads the Design Doc only** and produces:
   - **`01-epic.md`** at **`.ai-factory/state/projects/<slug>/01-epic.md`**, following **`.ai-factory/templates/epic.md`**
   - **`tasks/T<id>-<slug-or-name>.md`** under **`.ai-factory/state/projects/<slug>/tasks/`**, one file per task, following **`.ai-factory/templates/task.md`**

   Then **save the state**. Do the same after every revision of the plan

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

3. **Human quality gate — required:** **Wait for explicit human approval** of the task plan (epic + tasks + graph) before any **Stage 3** implementation work

4. **Stop** this skill. Next step: **[`factory-build`](../factory-build/SKILL.md)** — ready tasks run **in parallel** in their own worktrees, following the **dependency graph** (Coder → parallel Review + Verify → PR per task).

## What you must not do in Stage 2

| Do not | Why |
|--------|-----|
| Invoke **Coder**, **Reviewer**, or **Verifier** | Stage 3 — after plan approval |
| Plan from a **non-approved** or **missing** Design Doc | Plan must match agreed design |
| Give the **Coder** the Design Doc or full epic in this skill | Stage 3 passes one task + config only; Planner must embed spec context in each task |
| Omit **`## Task dependency graph`** or **Mermaid** that matches all tasks | Required for ordering and parallel work |

## Invoking subagents

Wherever this skill says *invoke the `factory-<name>` subagent*, call the Agent (Task) tool with `subagent_type: factory-<name>` and the input as the prompt.

Pass **only** the inputs this skill names (paths, task IDs) — subagents do not see this conversation. Users may also invoke the same subagents manually; behavior must match this procedure.

## Quick reference

| Output | Path |
|--------|------|
| Epic + graph | `.ai-factory/state/projects/<slug>/01-epic.md` |
| Task files | `.ai-factory/state/projects/<slug>/tasks/T<id>-<suffix>.md` |
| Design Doc (read-only input) | `.ai-factory/state/projects/<slug>/00-design.md` |
| Epic template | `.ai-factory/templates/epic.md` |
| Task template | `.ai-factory/templates/task.md` |

**Next stage:** **`factory-build`** — ready tasks in parallel worktrees: Coder, then parallel Reviewer + Verifier, then a PR per task, following the epic graph.

## Verification (for the agent)

- **`01-epic.md`** exists and includes **`## Task dependency graph`** with Mermaid covering all listed tasks
- **`tasks/`** contains **`.md`** files per task referenced in the epic; IDs line up with the graph
- **Human** has been prompted to **approve the plan** before treating Stage 2 as complete
