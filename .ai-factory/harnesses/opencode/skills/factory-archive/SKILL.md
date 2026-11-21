---
name: factory-archive
description: >-
  Factory archive: after a feature ships, moves a .ai-factory/state/projects/<slug>
  folder into a self-contained run under .ai-factory/state/archive/<slug>/<timestamp>/
  with 00-design.md, a single project-summary.md, and dependency-graph.md, saves it
  to the state branch, and offers to clean up the build's worktrees and branches.
  Use for factory archive cleanup, archive project <slug>, or retire a feature when
  work is done.
---

# Factory archive (project cleanup)

After a feature has shipped, **relocate the whole project bundle** into one timestamped directory under **`.ai-factory/state/archive/<slug>/<ts>/`**. There is **one** **`project-summary.md`** (in the archive only), plus **`00-design.md`** (moved, not edited) and **`dependency-graph.md`**. The directory **`.ai-factory/state/projects/<slug>/`** is removed. The removed files stay in the **state branch** history, and the summary records the commit that still has them. Then offer to clean up the build's leftover git worktrees and branches. **Never** delete or move **`.ai-factory/templates/`** — framework templates are out of scope.

## When to use

- The user wants to **archive** a factory project (e.g. “archive `my-feature`”, “archive project `my-feature`”, “clean up the factory project `oauth2`”).
- They want a **self-contained** record under **`.ai-factory/state/archive/`** and **no** leftover slug folder under **`.ai-factory/state/projects/`** (until they start a new feature with the same slug later).

## State branch

Everything the factory writes about a feature lives under **`.ai-factory/state/`**: work in progress in **`projects/<slug>/`** (Design Doc, evaluations, epic, task files, reports, **`build-state.md`**) and finished runs in **`archive/<slug>/<ts>/`**. That folder is a git worktree of the **state branch**, so it survives fresh clones, cloud sessions and other machines. **`config.md`** → **`## State`** → **`state_branch`** names the branch (default **`factory-state`**). If it is **`none`**, `.ai-factory/state/` is a plain folder and you skip the rest of this section: state stays on this machine only. The main checkout must gitignore **`.ai-factory/state/`**.

**Open the state** before you read or write anything under `.ai-factory/state/`:

1. If `.ai-factory/state/.git` exists, the worktree is already there. If its branch has an upstream, run `git -C .ai-factory/state pull --rebase`. Then stop here
2. If `.ai-factory/state/` exists and is not empty, or the old folders `.ai-factory/projects/` or `.ai-factory/archive/` hold files, this is state from before the state branch. Ask the human before migrating it: move `.ai-factory/state/` (if present) to `.ai-factory/state.local-backup/`, run step 3, copy the old content into `.ai-factory/state/projects/` and `.ai-factory/state/archive/` (if a slug exists on both sides, ask which to keep), **save the state**, and tell the human which old folders they can delete
3. Otherwise run `git fetch origin <state_branch>:refs/remotes/origin/<state_branch>`:
   - If that works, or a local `<state_branch>` branch exists, run `git worktree add .ai-factory/state <state_branch>`. If the branch is not on the remote yet, also run `git -C .ai-factory/state push -u origin <state_branch>`
   - If neither exists, create the branch with no files, check it out and push it:

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
git -C .ai-factory/state push
```

If the push is rejected, run `git -C .ai-factory/state pull --rebase` and push again. If the rebase conflicts, stop and ask the human. If you cannot push at all (no remote, or no permission), tell the human the state is saved only on this machine and carry on. **Never** force-push the state branch or merge it into another branch.

## Human quality gate (required)

1. **Open the state**, then **confirm the slug** — resolve to **`.ai-factory/state/projects/<slug>/`**. If the folder or **`00-design.md`** is missing, stop: say the project path is missing and suggest they check the slug.
2. **Check the build is finished.** Read **`build-state.md`** (if present) and every task file's status and **`## Delivery`**. If **`build-state.md`** Status is not **`complete`**, any task is not **`done`**, or the final PR from **`factory/<slug>`** into the base branch is not merged (check it with your GitHub tool when you can), list what is unfinished and ask the human whether to archive anyway. If **`build-state.md`** Status is **`active`** or **`handoff-pending`**, warn that archiving ends that build: a later resume will find nothing.
3. **Confirm relocation** — **`00-design.md`** will be **moved** into the archive run (not left in `projects/`). **Confirm removal** of **`01-epic.md`**, **`build-state.md`**, **`tasks/`**, **`evaluations/`**, **`reviews/`**, **`verifications/`**, and any other files in that project, and say they stay readable in the state branch history. No duplicate **`project-summary.md`**: a **single** file is written only inside the archive directory.
4. **Re-archive** — Each run uses a **new** **`<ts>`** folder. Older runs are left as-is.

## What you must not touch

| Location | Action |
|----------|--------|
| **`.ai-factory/templates/*`** | **Never** delete or move |
| **Other** slugs under `.ai-factory/state/projects/` | **Do not** touch |
| **`.ai-factory/examples/`** (default) | **Do not** archive unless the user **explicitly** gives a custom base path to example content |
| **`00-design.md` contents** | **Do not** edit; **move** the file as-is (same bytes) |
| The default branch, the base branch, and branches with **open** PRs | **Never** delete |

## Procedure

1. **Resolve** `projectRoot` = **`.ai-factory/state/projects/<slug>/`**. Require **`00-design.md`** to exist.
2. **Read** (before any delete or move):
   - **`00-design.md`**
   - **`01-epic.md`** and **`build-state.md`** (if present)
   - All **`*.md`** under **`tasks/`**, **`evaluations/`**, **`reviews/`**, **`verifications/`** (if those directories exist)
   - Any other **`*.md`** in **`projectRoot`** except **`00-design.md`**
3. **Record the source commit**: with a state branch, **save the state** first, then note `git -C .ai-factory/state rev-parse HEAD`. This commit still has every file you are about to remove.
4. **Create** **`.ai-factory/state/archive/<slug>/<ts>/`** where **`<ts>`** is **ISO-8601 local** or **`YYYY-MM-DD_HHmm`**.
5. **Write** **`dependency-graph.md`** in the archive run (**## Task dependency graph** + mermaid + **Legend** from `01-epic.md` when available; else a short note).
6. **Compose** **`project-summary.md`** (summarized) **only** into the archive run path **`.ai-factory/state/archive/<slug>/<ts>/project-summary.md`**:
   - **Metadata**: slug, archive timestamp, one line that **`00-design.md`** is in **this** directory (same folder), the **state branch** and **source commit** from step 3 (or "local only" without a state branch)
   - **Delivery**: base branch, epic branch **`factory/<slug>`**, and the final PR link and its state (merged, open, or none)
   - **Link to the Design Doc**: **`./00-design.md`**
   - **Link to the graph**: **`./dependency-graph.md`**
   - **Epic (text)**: title/summary, task list table from `01-epic.md` — no mermaid
   - **Design Doc evaluation** (if any under `evaluations/`): verdict, date, high-signal bullets
   - **Per task**: id, title, final status, objective one-liner, scenario titles, PR link, iterations used (**`## Delivery`**), review + verification outcomes, and one line each on any **`## Escalation`** or **`## Human Feedback`**
   - **Notes from the human** in **`build-state.md`**, if any, as short bullets
   - **Appendix (optional)**: source filenames read for the run
7. **Move** **`projectRoot/00-design.md`** → **`.ai-factory/state/archive/<slug>/<ts>/00-design.md`** (use `git mv` inside the state worktree, or `mv`; do not change file contents).
8. **Delete** the rest of **`projectRoot`** (only after steps 5–7 succeed): **`01-epic.md`**, **`build-state.md`**, tree dirs **`tasks/`**, **`evaluations/`**, **`reviews/`**, **`verifications/`**, and any other files left under **`projectRoot`**.
9. **Remove** the now-empty **`.ai-factory/state/projects/<slug>/`** directory. If something unexpected is left, report what is left and ask whether to remove it.
10. **Save the state** (commit message `factory(<slug>): archive`).
11. **Offer git cleanup** of what the build left behind. List what exists, ask the human, and remove only what they approve:
    - Task worktrees: entries in `git worktree list` under `worktree_dir` (`config.md` → `## Build`, default `../<repo>-worktrees`) named **`<slug>-T<id>`**. Remove with `git worktree remove <path>`; if one has uncommitted changes, show them and ask before `--force`
    - Local branches **`factory/<slug>`** and **`factory/<slug>/T<id>`**: delete with `git branch -d` (`-D` only if the human approves, for a branch that is not merged)
    - Remote branches **`origin/factory/<slug>`** and **`origin/factory/<slug>/T<id>`** whose PRs are merged or closed: delete with `git push origin --delete <branch>`. Some cloud sessions refuse branch deletion; if so, tell the human to delete them on GitHub
12. **Report** paths: the single self-contained run **`.ai-factory/state/archive/<slug>/<ts>/`** with exactly **`00-design.md`**, **`project-summary.md`**, and **`dependency-graph.md`**; that **`projects/<slug>`** is gone; the source commit; whether the state was pushed; and what git cleanup was done or skipped.

## Edge cases

| Situation | Behavior |
|-----------|----------|
| Missing `01-epic.md` | **`project-summary`** from tasks/evals; **`dependency-graph.md`** = stub if needed |
| No task files | Still write graph stub + summary; remove empty `tasks/` if present |
| Missing `build-state.md` (build never started, or an older project) | Skip its parts of the summary; the step 2 check uses task statuses only |
| `state_branch` is `none` | No source commit and nothing is pushed; tell the human the removed files are gone for good and ask before step 8 |
| User wants **`.ai-factory/examples/...`** archived | Only if they **explicitly** set a custom `projectRoot` |

## Verification (for the agent)

- **`.ai-factory/state/archive/<slug>/<ts>/`** contains **exactly** three files: **`00-design.md`**, **`project-summary.md`**, **`dependency-graph.md`** (no second summary elsewhere).
- **`.ai-factory/state/projects/<slug>/`** no longer exists.
- **`00-design.md`** was moved, not edited; **`.ai-factory/templates/`** untouched.
- With a state branch, the archive commit is pushed (or the human was told it is local only) and **`project-summary.md`** names the source commit.
- No worktree or branch was removed without the human's approval.
