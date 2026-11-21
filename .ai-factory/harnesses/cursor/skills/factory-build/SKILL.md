---
name: factory-build
description: >-
  Stage 3 (Build) — run every ready task from the 01-epic dependency graph in
  parallel, each on its own branch and git worktree: factory-coder, then
  factory-reviewer and factory-verifier in parallel, retry up to max_iterations,
  then open a PR per task into the epic branch. Merging the PR is the human
  sign-off. Use for implement T001, build the epic, coding stage, CR loop,
  review verify loop, resume the build, hand off the build.
---

# Stage 3 (Build) — parallel tasks, each Coder → parallel Review + Verify → PR

**Stage 3** — Work out which tasks are **ready** (every prerequisite **`done`**) from the
**`01-epic.md`** graph and run them **concurrently**, each on its own **branch** and **git
worktree**. Each task loops **Coder** → **Reviewer** and **Verifier** in parallel →
reconcile, up to **`max_iterations`** times. A task that passes gets a **pull request**
into the **epic branch**. The human **merges the PR** to sign off, which marks the task
**`done`** and can make new tasks ready. When every task is **`done`**, open one PR from the
epic branch to the base branch for the final merge.

This skill does **not** replace **`.ai-factory/config.md`** for the Verifier or the
**one-task-in-prompt** contract for the Coder.

## When to use

- **`.ai-factory/projects/<slug>/01-epic.md`** and **`tasks/T<id>-*.md`** exist and the **task plan is human-approved**
- User says *build the epic*, *implement T001*, *run the CR loop*, *continue the build*, *resume the build*, *T002's PR is merged*

## Preconditions

1. **`<slug>`** resolved — **`.ai-factory/projects/<slug>/`**
2. **`01-epic.md`** and its **task dependency graph** define the order (`T001 --> T002` means T002 depends on T001)
3. **`.ai-factory/config.md`** present, including its **`## Build`** settings (defaults below if a row is missing)
4. The project is a **git** repository with a remote, and you can push and open pull requests (for example with the `gh` CLI). If you cannot open a PR, stop and tell the human; do not fall back to merging locally
5. **`.ai-factory/projects/` is gitignored** (check with `git check-ignore -q .ai-factory/projects/<slug>/01-epic.md`). If it is tracked, every worktree would get its own stale copy of the task files and status writes would dirty the main checkout, so stop and offer to add `.ai-factory/projects/*` to `.gitignore` (and untrack it with `git rm -r --cached .ai-factory/projects` if needed) before building
6. The working tree of the main checkout is clean, or the human agrees to proceed

## Build settings (`config.md` → `## Build`)

| Setting | Default | Meaning |
|---|---|---|
| `max_concurrent_tasks` | `3` | Most tasks running a Coder / Review / Verify loop at once. `1` runs tasks one at a time |
| `max_iterations` | `3` | Most Coder passes per task before it is `blocked` and escalated |
| `worktree_dir` | `../<repo>-worktrees` | Where task worktrees go, relative to the repo root. Keep it outside the repo |
| `base_branch` | the branch checked out when the build starts | Branch the epic branch is created from and the final PR targets |
| `handoff_after_rounds` | `6` | Rounds (one Step C, across all tasks) this orchestrator session runs before it hands off to a fresh one. `0` turns the count off |
| `handoff_at_percent` | `70` | Context usage at which an installed factory hook or plugin asks you to hand off. You do not measure it yourself |

## Branches and worktrees

| Thing | Name |
|---|---|
| Epic branch | `factory/<slug>` |
| Task branch | `factory/<slug>/T<id>` |
| Task worktree | `<worktree_dir>/<slug>-T<id>` |

- **Never** commit to, push to, or merge into the **default branch** or **`base_branch`**. Only the final PR targets it, and the human merges it
- **Task files, reports and `config.md` stay in the main checkout.** `.ai-factory/projects/` is the single source of truth for status and is not part of any worktree. Pass **absolute** main-checkout paths to subagents
- Code changes happen **only** inside a task's worktree, committed to its task branch
- **`build-state.md`** (see [Build state](#build-state)) lives with the task files in the main checkout

## Context isolation (strict)

| Role | Receives | Must not receive **in the agent prompt** |
|------|----------|-------------------------------------------|
| **Coder** | Absolute **task file path**, absolute **`config.md` path**, **worktree path**, **epic branch**; full repository inside the worktree | Design Doc, epic, other tasks as pasted context |
| **Reviewer** | Absolute **task file path**, **worktree path**, **epic branch** (for the diff) | Writing any file *(read-only; returns its report)* |
| **Verifier** | Absolute **`config.md` path**, **task ID** (e.g. `T001`), **worktree path** | Full task prose / feature context; writing any file *(read-only; returns its report)* |

## Build state

**`.ai-factory/projects/<slug>/build-state.md`** (shape: **`.ai-factory/templates/build-state.md`**) lets a fresh orchestrator pick up the build when this one runs low on context. Task files stay the source of truth for status, iterations, feedback and PR links. The state file holds only what they do not: tasks in flight and the step each is on, build-wide instructions the human gave in chat, what is waiting on the human, the next step, and the round count for this session.

- You are its only writer. Keep it short: point to task files, never copy task text or reports into it
- **Rewrite it at every checkpoint:** after Step 0, whenever a task enters a new step (A to E), after each Scheduler pass, whenever the human gives an instruction in chat, and at a handoff
- **Human instructions** given in chat: task-specific ones go in that task file as **`## Human Feedback`**; build-wide ones go under **Notes from the human**. Nothing the human said may live only in the conversation
- **Rounds this session:** add one each time a task finishes Step C. It drives `handoff_after_rounds`
- If the state file disagrees with a task file or with GitHub, the task file and GitHub win

## Step 0 — Set up the epic branch (once per build)

If **`build-state.md`** exists with Status **`active`** or **`handoff-pending`**, follow **[Resume](#resume)** instead of starting fresh.


1. Resolve `base_branch` (setting, else the current branch). Tell the human which base you are using
2. If `origin/factory/<slug>` does not exist, push the epic branch: reuse the local `factory/<slug>` if there is one, otherwise create it from `base_branch`, then `git push -u origin factory/<slug>`
3. Otherwise fetch it: `git fetch origin factory/<slug>`. Step A always branches from `origin/factory/<slug>`

## Scheduler

Repeat until every task is `done`, or nothing can move:

1. **Refresh merged PRs.** For each task with status **`in-review`**, check its PR. If merged, run **Step E**. If closed without merging, tell the human and leave the task `in-review` until they decide
2. **Compute the ready set:** tasks with status **`draft`** whose prerequisites are all **`done`**. A prerequisite that is `in-review` is **not** done; its dependents wait
3. **Launch** ready tasks until `max_concurrent_tasks` tasks are in **`in-progress`** or **`implemented`**. Launching a task means **Step A** for it
4. Run each launched task's **loop** (Steps B → D) independently. Tasks never wait on each other's loops; when one finishes, go back to step 1 and launch more
5. **Stop** when no task is running and no task is ready. Report every task's status to the human: `done`, `in-review` with PR links waiting for their merge, `blocked` with escalation summaries, and `draft` tasks still waiting on prerequisites

If your harness cannot run subagents concurrently, run the same scheduler with one task at a time.

Before launching anything in step 3, check the [handoff triggers](#context-handoff). If one has fired, hand off instead.

## Resume

Use when **`build-state.md`** exists with Status **`active`** or **`handoff-pending`**: an earlier orchestrator handed off, or its session ended mid-build.

1. Read **`build-state.md`**, **`config.md`**, **`01-epic.md`** and every task file. Do not rely on anything from an earlier conversation
2. Run **Step 0** (it is safe to repeat)
3. Put each task back at its resume point:

   | Task status | Resume at |
   |---|---|
   | `draft` | The Scheduler, as usual |
   | `in-progress` | **Step B**. If the state file says the Coder had not returned (the session ended inside Step B), do not increment **Iteration** again; the Coder picks up any uncommitted work in the worktree |
   | `implemented` | **Step C**, or **Step D** if the task file's **`## Review & Verification`** already holds both reports for the current iteration |
   | `in-review` | Scheduler step 1 (check the PR) |
   | `blocked` | Nothing. Remind the human it is waiting on them |
   | `done` | Step E cleanup, only if its worktree or local branch still exists |

4. Follow every entry under **Notes from the human**
5. Set Status to **`active`**, reset **Rounds this session** to `0`, and tell the human in two or three lines what you resumed (tasks running, PRs waiting, blocked tasks). Do not wait for a reply
6. Enter the **Scheduler**

## Context handoff

Your context fills as subagent reports come back. Hand off to a fresh orchestrator before it runs out or gets compacted.

**Triggers** (any one):

- **Rounds this session** reached `handoff_after_rounds` (unless it is `0`)
- A factory hook or plugin told you context usage passed `handoff_at_percent`
- The human asks you to hand off
- Your earlier conversation was summarized or compacted. First re-read **`build-state.md`** and every task file (never trust a summary for task state), then hand off at the next safe point

**Steps:**

1. Launch no new task and start no new **Step B**
2. Tasks already inside Step B or C finish that step and Step D's bookkeeping: persist reports, append feedback, then open the PR or escalate. Do not wait on the human (PR merges, answers)
3. Rewrite **`build-state.md`** with Status **`handoff-pending`**, each task in flight with the step it resumes at, and a **Next step**
4. Tell the human, then stop. Use this message, filling in the path and slug:

   > My context is getting full, so I saved the build state to `<path to build-state.md>`. To continue with a fresh orchestrator, clear this conversation and then say **resume the factory build for `<slug>`**.
   >
   > | Harness | Clear with |
   > |---|---|
   > | Claude Code | `/clear` |
   > | Cursor | Start a new chat |
   > | OpenCode | `/new` |

Do no more build work after handing off; the next orchestrator owns the build.

## Per-task loop

### Step A — Create the task's branch and worktree

1. `git fetch origin factory/<slug>` so dependents start from the latest merged prerequisites
2. `git worktree add <worktree_dir>/<slug>-T<id> -b factory/<slug>/T<id> origin/factory/<slug>`. If the branch or worktree already exists (resumed build), reuse it
3. If `config.md` has an **Install** command, run it inside the worktree
4. In the task file, fill **`## Delivery`** (branch, worktree, iteration `0 / <max_iterations>`) and set status to **`in-progress`**

### Step B — Implement

1. Increment the task file's **Iteration** count
2. **Invoke the `factory-coder` subagent** with the task file path, the `config.md` path, the worktree path and the epic branch
3. The Coder works and commits only in the worktree, and sets status to **`implemented`** (or **`blocked`**, which stops this task's loop; report it to the human)
4. **Coder autonomy:** implementation choices and optional Reviewer nits stay with the Coder. **Every** Gherkin scenario **must** pass

### Step C — Review and Verify (**parallel** — do not sequentialize)

**Launch together:**

- **`factory-reviewer`** with the task file path, the worktree path and the epic branch
- **`factory-verifier`** with the task ID, the `config.md` path and the worktree path — **not** the task markdown body

**Never skip** this pair.

**Persist both reports.** Reviewer and Verifier are **read-only** and return their reports as text. After both return:

1. Write the Reviewer report to **`.ai-factory/projects/<slug>/reviews/T<id>-review.md`** (shape: **`.ai-factory/templates/review.md`**)
2. Write the Verifier report to **`.ai-factory/projects/<slug>/verifications/T<id>-verify.md`** (shape: **`.ai-factory/templates/verify.md`**)
3. Update the task file's **`## Review & Verification`** section: status, a one-line key-findings summary, and the report paths

The orchestrator is the only writer of these files, so parallel tasks never race on them.

### Step D — Reconcile

| Reviewer | Verifier | Action |
|----------|----------|--------|
| pass | pass | **Open the PR** (below) |
| revisions-needed | anything | **Append** Reviewer feedback to the task file (never delete earlier feedback) |
| anything | fail | **Append** Verifier output to the task file |

After appending, check the iteration count:

- **Below `max_iterations`:** go back to **Step B** with the same inputs
- **At `max_iterations`:** **escalate.** Set status to **`blocked`**, add a **`## Escalation`** section to the task file summarizing each iteration's failures (what failed, what the Coder tried, what still fails), and show that summary to the human. Keep the worktree and branch for inspection. Other tasks keep running; this task's dependents wait. When the human resolves it (edits the task or adds guidance) and asks to resume, reset **Iteration** to `0`, set status to **`in-progress`** and run Step B on the same branch and worktree

**Open the PR** when both pass:

1. Push the task branch: `git push -u origin factory/<slug>/T<id>`
2. Open a PR (ready for review, not draft) from `factory/<slug>/T<id>` into **`factory/<slug>`**, titled `T<id>: <task title>`. In the body include: the task objective, the scenario list, the Reviewer and Verifier verdicts with key findings, the local report paths, and the iteration count
3. Record the PR URL in **`## Delivery`** and set status to **`in-review`**
4. Tell the human the PR is ready. **Merging it is Quality Gate 3 (task sign-off).** Do not merge it yourself

If the PR has a merge conflict with `factory/<slug>` (for example a sibling merged first), tell the human. **Never** resolve conflicts automatically or force-push. If the human asks for a fix, append their instructions as feedback, reset **Iteration** to `0` and run Step B. Earlier automated rounds do not count against this fix; its own retries count normally.

If the human requests changes on the PR, append their comments to the task file as **`## Human Feedback`**, set status back to **`in-progress`** and run **Steps B → D** on the same branch and worktree. Reset **Iteration** to `0` first, so earlier automated rounds do not count against the human round; its own retries count normally. Push the new commits to the same PR instead of opening another.

### Step E — PR merged (task done)

1. Set the task status to **`done`**
2. `git worktree remove <worktree_dir>/<slug>-T<id>` and delete the local task branch
3. Return to the **Scheduler**: dependents may now be ready

## All tasks done (Stage 4: Ship)

When every task is **`done`**, open one PR from **`factory/<slug>`** into **`base_branch`** with a completion summary (tasks, PR links, notable findings), and set **`build-state.md`** Status to **`complete`**. **Merging it is Quality Gate 4 (final merge)** — the human does it. Optionally use **`factory-archive`** once the feature is retired.

## What you must not do in Stage 3

| Do not | Why |
|--------|-----|
| Start a task whose prerequisites are not all **`done`** (merged) | Dependents build on merged prerequisite code |
| Run more than `max_concurrent_tasks` task loops at once | Configured limit |
| Run Reviewer and Verifier **sequentially** or **omit one** | **Parallel** Review + Verify is required |
| Paste **task text** into the **Verifier** | **config.md** (+ task ID + worktree) only |
| Put **Design Doc** or **epic** into the **Coder** prompt | The task file is the spec |
| **Remove** previous feedback when re-invoking Coder | **Append** only |
| Re-invoke the Coder past `max_iterations` without the human | Escalate instead |
| Commit to, push to or merge into the default branch or `base_branch` | Only the human merges the final PR |
| Merge a task PR, resolve merge conflicts or force-push | The PR merge is the human's sign-off |
| Trust a compacted summary over task files and **`build-state.md`** | Summaries drop detail; disk is the source of truth |
| Keep working after a handoff, or leave a human instruction only in the conversation | The next orchestrator sees only what is on disk |

## Invoking subagents

Wherever this skill says *invoke the `factory-<name>` subagent*, delegate to the subagent by name (e.g. `/factory-<name> <input>`). To run tasks or the Reviewer + Verifier pair concurrently, delegate to the subagents together in the same turn.

Pass **only** the inputs this skill names (paths, task IDs, branch) — subagents do not see this conversation. Users may also invoke the same subagents manually; behavior must match this procedure.

Example inputs:

```text
factory-coder     Implement /abs/repo/.ai-factory/projects/<slug>/tasks/T001-<name>.md
                  config: /abs/repo/.ai-factory/config.md
                  worktree: /abs/repo-worktrees/<slug>-T001
                  epic branch: factory/<slug>
factory-reviewer  Review /abs/repo/.ai-factory/projects/<slug>/tasks/T001-<name>.md
                  worktree: /abs/repo-worktrees/<slug>-T001
                  epic branch: factory/<slug>
factory-verifier  Verify T001
                  config: /abs/repo/.ai-factory/config.md
                  worktree: /abs/repo-worktrees/<slug>-T001
```

## Quick reference

| Item | Value |
|------|--------|
| Task files | `.ai-factory/projects/<slug>/tasks/T<id>-*.md` (main checkout) |
| Order | **`01-epic.md`** task dependency graph; a task is ready when all prerequisites are `done` |
| Statuses | `draft` → `in-progress` → `implemented` → `in-review` → `done`; `blocked` on Coder blocker or retry cap |
| Parallel step | **`factory-reviewer`** + **`factory-verifier`** per iteration; tasks themselves run concurrently |
| Task sign-off | Human merges the task PR into `factory/<slug>` |
| Build state | `.ai-factory/projects/<slug>/build-state.md`, rewritten at every checkpoint; read by **Resume** |
| Final merge | Human merges `factory/<slug>` into `base_branch` |

**Previous stage:** approved plan (**`factory-plan`**).

## Verification (for the agent)

- Only tasks with every prerequisite **`done`** were launched, never more than `max_concurrent_tasks` at once
- Each task ran in its own worktree on `factory/<slug>/T<id>`; nothing was committed to the default branch or `base_branch`
- **Reviewer + Verifier** launched **in parallel** each iteration, and both reports were written by the orchestrator
- Feedback was **appended**, the iteration count was tracked, and a task at `max_iterations` was set **`blocked`** with an **`## Escalation`** summary
- Each passing task has a PR into `factory/<slug>` recorded in its task file; a task became **`done`** only after its PR was merged
- **`build-state.md`** was rewritten at every checkpoint, and a fired handoff trigger ended in Status **`handoff-pending`** and the clear-and-resume message
