---
name: sdlc-archive
description: >-
  SDLC archive: moves a .sdlc/projects/<slug> folder into a self-contained run
  under .sdlc/archive/<slug>/<timestamp>/ with 00-tdd.md, a single
  project-summary.md, and dependency-graph.md. Deletes the slug directory under
  projects. Use for SDLC archive cleanup, archive project <slug>, or retire a
  feature when work is done.
---

# SDLC archive (project cleanup)

After a feature is done, **relocate the whole project bundle** into one timestamped directory under **`.sdlc/archive/<slug>/<ts>/`**. There is **one** **`project-summary.md`** (in the archive only), plus **`00-tdd.md`** (moved, not edited) and **`dependency-graph.md`**. The directory **`.sdlc/projects/<slug>/`** is removed when empty. **Never** delete or move **`.sdlc/templates/`** — framework templates are out of scope.

## When to use

- The user wants to **archive** an **SDLC** / **.sdlc/projects** project (e.g. “SDLC archive for `my-feature`”, “archive project `my-feature`”, “clean up SDLC for `oauth2`”).
- They want a **self-contained** record under **`.sdlc/archive/`** and **no** leftover slug folder under **`.sdlc/projects/`** (until they start a new feature with the same slug later).

## Human gate (required)

1. **Confirm the slug** — resolve to **`.sdlc/projects/<slug>/`**. If the folder or **`00-tdd.md`** is missing, stop: say the project path is missing and suggest they check the slug.
2. **Confirm relocation** — **`00-tdd.md`** will be **moved** into the archive run (not left in `projects/`). **Confirm destruction** of **`01-epic.md`**, **`tasks/`**, **`evaluations/`**, **`reviews/`**, **`verifications/`**, and any other supporting **`*.md`** in that project. No duplicate **`project-summary.md`**: a **single** file is written only inside the archive directory.
3. **Re-archive** — Each run uses a **new** **`<ts>`** folder. Older runs are left as-is. If **`project-summary.md`** exists only under the old project path (from a pre-change workflow), delete it during cleanup.

## What you must not touch

| Location | Action |
|----------|--------|
| **`.sdlc/templates/*`** | **Never** delete or move |
| **Other** `.sdlc/projects/*` **slugs** | **Do not** touch |
| **`.sdlc/examples/`** (default) | **Do not** archive unless the user **explicitly** gives a custom base path to example content |
| **`00-tdd.md` contents** | **Do not** edit; **move** the file as-is (same bytes) |

## Procedure

1. **Resolve** `projectRoot` = **`.sdlc/projects/<slug>/`**. Require **`00-tdd.md`** to exist.
2. **Read** (before any delete or move):
   - **`00-tdd.md`**
   - **`01-epic.md`** (if present)
   - All **`*.md`** under **`tasks/`**, **`evaluations/`**, **`reviews/`**, **`verifications/`** (if those directories exist)
   - Any other **`*.md`** in **`projectRoot`** except **`00-tdd.md`** (e.g. stray or legacy **`project-summary.md`** to drop)
3. **Create** **`.sdlc/archive/<slug>/<ts>/`** where **`<ts>`** is **ISO-8601 local** or **`YYYY-MM-DD_HHmm`**.
4. **Write** **`dependency-graph.md`** in the archive run (same rules as before: **## Task dependency graph** + mermaid + **Legend** from `01-epic.md` when available; else a short note).
5. **Compose** **`project-summary.md`** (summarized) **only** into the archive run path **`.sdlc/archive/<slug>/<ts>/project-summary.md`**:
   - **Metadata**: slug, archive timestamp, one line that **`00-tdd.md`** is in **this** directory (same folder)
   - **Link to the TDD**: **`./00-tdd.md`**
   - **Link to the graph**: **`./dependency-graph.md`**
   - **Epic (text)**: title/summary, task list table from `01-epic.md` — no mermaid
   - **TDD evaluation** (if any under `evaluations/`): verdict, date, high-signal bullets
   - **Per task**: id, title, final status, objective one-liner, scenario titles, review + verification outcomes
   - **Appendix (optional)**: source filenames read for the run
6. **Move** **`projectRoot/00-tdd.md`** → **`.sdlc/archive/<slug>/<ts>/00-tdd.md`** (use `mv` / `git mv` as appropriate; do not change file contents).
7. **Delete** the rest of **`projectRoot`** (only after steps 4–6 succeed):
   - **`01-epic.md`**, tree dirs **`tasks/`**, **`evaluations/`**, **`reviews/`**, **`verifications/`**, and any other **`*.md`** or files left under **`projectRoot`**
8. **Remove** the now-empty **`.sdlc/projects/<slug>/`** directory (e.g. `rmdir` or `rm -rf` the slug folder if the tool leaves an empty directory). If non-empty (e.g. only dotfiles), report what is left and ask whether to remove.
9. **Report** paths: the single self-contained run **`.sdlc/archive/<slug>/<ts>/`** with exactly **`00-tdd.md`**, **`project-summary.md`**, and **`dependency-graph.md`**; that **`projects/<slug>`** is gone. Remind: **`projects/`** and **`archive/`** are often **gitignored** in this framework.

## Git / ignore behavior

- In this framework repo, **`.sdlc/projects/*`** and **`.sdlc/archive/*`** are usually **gitignored**; local data stays on disk unless force-added. Mention that in the handoff.

## Edge cases

| Situation | Behavior |
|-----------|----------|
| Missing `01-epic.md` | **`project-summary`** from tasks/evals; **`dependency-graph.md`** = stub if needed |
| No task files | Still write graph stub + summary; remove empty `tasks/` if present |
| Legacy **`project-summary.md`** in `projectRoot` | Delete when cleaning **`projectRoot`** (step 7) — only one summary exists in the archive run |
| User wants **`.sdlc/examples/...`** archived | Only if they **explicitly** set a custom `projectRoot` |

## Verification (for the agent)

- **`.sdlc/archive/<slug>/<ts>/`** contains **exactly** three files: **`00-tdd.md`**, **`project-summary.md`**, **`dependency-graph.md`** (no second summary elsewhere).
- **`.sdlc/projects/<slug>/`** no longer exists (or is empty and removed per step 8).
- **`00-tdd.md`** was moved, not edited; **`.sdlc/templates/`** untouched.
