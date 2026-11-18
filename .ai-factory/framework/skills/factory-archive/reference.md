# SDLC archive skill: example outputs

Illustrative fragments for **`dependency-graph.md`** and **`project-summary.md`**, based on **`.sdlc/examples/oauth2/`**. That example has no `01-epic.md`; a real run with an epic copies the **## Task dependency graph** section from `01-epic.md` verbatim into `dependency-graph.md`. After a run, **`00-tdd.md`** lives **only** in **`.sdlc/archive/<slug>/<ts>/00-tdd.md`**, moved from **`projects/<slug>/`**.

## Example: dependency-graph.md (synthetic, when epic is missing)

When `01-epic.md` is absent, the skill may emit a short stub plus any graph recovered from the task list. A minimal file might start like:

- Title line: `# OAuth2 (example) — no epic on disk`
- Body: a short note that `01-epic.md` was not found, plus optional mermaid if inferred from task IDs.

With a real epic present, the file should include the full **## Task dependency graph** content from the epic: prerequisite paragraph, mermaid `flowchart` block, and **### Legend** (per **`.sdlc/templates/epic.md`**).

## Example: project-summary.md (structure only)

- **Metadata table**: slug, archive ISO timestamp, one line that **`00-tdd.md`** sits beside this file in **`.sdlc/archive/<slug>/<ts>/`**
- **Link to the TDD**: **`./00-tdd.md`**
- **Link to the graph**: **`./dependency-graph.md`**
- **Epic (text)**: copy or shorten title, summary, and task list table from `01-epic.md` (no mermaid in this file)
- **TDD evaluation** (from `evaluations/`): e.g. for `00-tdd-evaluation.md` — **verdict** `needs-revision`, **date** `2026-04-21`, bullets on critical findings
- **Per task** (from `tasks/T*.md`): e.g. **T001** — title, one-line objective, Gherkin scenario titles, review/verify summaries
- **Appendix**: `evaluations/00-tdd-evaluation.md`, `tasks/T001-add-oauth-providers.md` (as read for the run; originals are not kept)

This file is a **shape** reference; the agent should fill in real text from the user’s project, not copy this example.
