---
name: sdlc-archive
description: >-
  SDLC archive: summarizes a local .sdlc/projects feature folder (tasks, reviews,
  verifications, evaluations, epic) into project-summary.md, writes
  dependency-graph.md under .sdlc/archive, and deletes supporting markdown;
  leaves 00-tdd.md unchanged. Use when the user wants to archive an SDLC
  project, SDLC archive cleanup, clean up .sdlc/projects, or retire a feature
  slug after the TDD is the only long-lived artifact.
---

# SDLC archive (project cleanup)

Clean up a per-project folder under **`.sdlc/projects/<slug>/`** (default scope). The TDD remains; everything else is summarized, two files are written per archive run, then the supporting markdown trees are removed. **Never** delete or move **`.sdlc/templates/`** — framework templates are out of scope.

## When to use

- The user says they want to **archive** an **SDLC** / **.sdlc/projects** project (e.g. “SDLC archive for `my-feature`”, “archive project `my-feature`”, “clean up SDLC for `oauth2`”).
- They want a **lean** `.sdlc/projects/<slug>/` with only `00-tdd.md` plus a rolling **`project-summary.md`**.

## Human gate (required)

1. **Confirm the slug** — resolve to **`.sdlc/projects/<slug>/`**. If the folder or **`00-tdd.md`** is missing, stop: say the project path is missing and suggest they check the slug.
2. **Confirm destruction** — Original **`01-epic.md`**, **`tasks/`**, **`evaluations/`**, **`reviews/`**, **`verifications/`**, and other supporting **`*.md`** in that project (except `00-tdd.md` and the new/updated `project-summary.md`) **will be deleted** after a successful write. No full copies of those files are kept; only the archive run’s two markdown files retain the graph + summary.
3. **Re-archive** — If **`project-summary.md`** already exists from a past run, **replace** it with the new run’s content. Each run must use a **new** timestamp folder under **`.sdlc/archive/`**; do not overwrite prior run folders unless the user explicitly asks.

## What you must not touch

| Location | Action |
|----------|--------|
| **`.sdlc/projects/<slug>/00-tdd.md`** | **Never** delete, move, or modify |
| **`.sdlc/templates/*`** | **Never** delete or move |
| **Other** `.sdlc/projects/*` **slugs** | **Do not** touch |
| **`.sdlc/examples/`** (default) | **Do not** archive unless the user **explicitly** gives a custom base path to example content |

## Procedure

1. **Resolve** `projectRoot` = **`.sdlc/projects/<slug>/`**. Require **`00-tdd.md`** to exist.
2. **Read** (before any delete):
   - **`01-epic.md`** (if present)
   - All **`*.md`** under **`tasks/`**, **`evaluations/`**, **`reviews/`**, **`verifications/`** (if those directories exist)
   - Any other **`*.md`** in **`projectRoot`** **except** `00-tdd.md` and (for reading strategy) note existing **`project-summary.md`** to replace
   - If a directory is empty or missing, continue; do not error solely for emptiness
3. **Create archive run directory**: **`.sdlc/archive/<slug>/<ts>/`** where `<ts>` is **ISO-8601 local** or **`YYYY-MM-DD_HHmm`** so repeated archives do not collide.
4. **Write** **`dependency-graph.md`** in the archive run:
   - Prefer extracting, **verbatim**, the epic’s **`## Task dependency graph`** section: include the “Prerequisite direction” paragraph (if it appears under that section), the fenced mermaid code block, and the **Legend** subsection (template uses **`### Legend`** under that heading).
   - If the epic uses different headings, still capture the mermaid **flowchart** block **plus** the closest Legend section following [`.sdlc/templates/epic.md`](.sdlc/templates/epic.md). If there is no mermaid in `01-epic.md`, write a short note in **`dependency-graph.md`** that no graph was found and, if any, paste raw dependencies from the task list.
   - Optional first line: epic title (from first `#` in `01-epic.md` if any) and source path e.g. `.sdlc/projects/<slug>/01-epic.md`.
5. **Compose** **`project-summary.md`** (summarized, not a full copy of every file):
   - **Metadata**: slug, archive timestamp, one line that **`00-tdd.md`** was left unchanged
   - **Where the graph lives**: relative path from **`.sdlc/projects/<slug>/project-summary.md`** to **`../../archive/<slug>/<ts>/dependency-graph.md`** (adjust `../` depth if needed) so the reader can open the graph file
   - **Epic (text)**: title/summary if present, **task list table** (ID, title, depends on) from `01-epic.md` — **do not** paste the mermaid into this file
   - **TDD evaluation** (if any files under `evaluations/`): verdict, date, a handful of high-signal bullets
   - **Per task** (order by T001, T002, … or epic order): id, title, final status, one-line objective, scenario **titles** (or very short), review verdict and highlights, verification pass/fail and failed commands if any
   - **Appendix (optional)**: list of source filenames that were read for this run
6. **Write** **`project-summary.md`** to **`.sdlc/projects/<slug>/project-summary.md`** (overwrite if re-archiving).
7. **Write** a **byte-identical** copy to **`.sdlc/archive/<slug>/<ts>/project-summary.md`** so the archive run is self-contained (**exactly two** markdown files in that folder: `dependency-graph.md` and `project-summary.md`).
8. **Delete** from **`projectRoot`** (only if steps 4–7 succeeded):
   - **`01-epic.md`** if present
   - Directories **`tasks/`**, **`evaluations/`**, **`reviews/`**, **`verifications/`** — remove the **tree** (all files; remove empty parents if applicable)
   - Any other **`*.md`** in `projectRoot` **except** `00-tdd.md` and `project-summary.md`
   - Do **not** leave stray copies of the old full task files anywhere under `projectRoot`
9. **Report** to the user: final layout (`00-tdd.md` + `project-summary.md` in `projects/`), path to the archive run, reminder that `projects/` and `archive/` are typically **gitignored** in this framework.

## Git / ignore behavior

- In this framework repo, **`.sdlc/projects/*`** and **`.sdlc/archive/*`** are usually **ignored** in git; local archive runs stay on disk only unless the user force-adds. Mention that in the handoff.

## Edge cases

| Situation | Behavior |
|-----------|----------|
| Missing `01-epic.md` | Build **`project-summary`** from tasks/evals only; **`dependency-graph.md`** = short note, no mermaid |
| No task files | Still write summary + graph stub if applicable; delete `tasks/` if empty or missing (noop) |
| Re-run archive on same slug | New **`<ts>`** folder; replace **`project-summary.md`** in `projects/` |
| User wants **`.sdlc/examples/...`** archived | Only if they **explicitly** set the project root; default remains **`.sdlc/projects/<slug>`** only |

## Verification (for the agent)

- **`.sdlc/projects/<slug>/`** contains only **`00-tdd.md`** and **`project-summary.md`** (plus no leftover `tasks`/`reviews`/`verifications`/`evaluations` content).
- **`.sdlc/archive/<slug>/<ts>/`** contains **only** **`dependency-graph.md`** and **`project-summary.md`**.
- **`00-tdd.md`** unchanged; **`.sdlc/templates/`** untouched.
