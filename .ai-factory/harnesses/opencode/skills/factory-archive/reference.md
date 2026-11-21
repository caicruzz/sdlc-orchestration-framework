# Factory archive skill: example outputs

Illustrative fragments for **`dependency-graph.md`** and **`project-summary.md`**, based on **`.ai-factory/examples/oauth2/`**. That example has no `01-epic.md`; a real run with an epic copies the **## Task dependency graph** section from `01-epic.md` verbatim into `dependency-graph.md`. After a run, **`00-design.md`** lives **only** in **`.ai-factory/state/archive/<slug>/<ts>/00-design.md`**, moved from **`.ai-factory/state/projects/<slug>/`**.

## Example: dependency-graph.md (synthetic, when epic is missing)

When `01-epic.md` is absent, the skill may emit a short stub plus any graph recovered from the task list. A minimal file might start like:

- Title line: `# OAuth2 (example) — no epic on disk`
- Body: a short note that `01-epic.md` was not found, plus optional mermaid if inferred from task IDs.

With a real epic present, the file should include the full **## Task dependency graph** content from the epic: prerequisite paragraph, mermaid `flowchart` block, and **### Legend** (per **`.ai-factory/templates/epic.md`**).

## Example: project-summary.md (structure only)

- **Metadata table**: slug, archive ISO timestamp, one line that **`00-design.md`** sits beside this file in **`.ai-factory/state/archive/<slug>/<ts>/`**, state branch and source commit (e.g. `factory-state` @ `3f2a9c1`)
- **Delivery**: base branch `main`, epic branch `factory/oauth2`, final PR link and whether it is merged
- **Link to the Design Doc**: **`./00-design.md`**
- **Link to the graph**: **`./dependency-graph.md`**
- **Epic (text)**: copy or shorten title, summary, and task list table from `01-epic.md` (no mermaid in this file)
- **Design Doc evaluation** (from `evaluations/`): e.g. for `00-design-evaluation.md` — **verdict** `needs-revision`, **date** `2026-04-21`, bullets on critical findings
- **Per task** (from `tasks/T*.md`): e.g. **T001** — title, final status, one-line objective, Gherkin scenario titles, PR link, iterations used, review/verify summaries, and any escalation or human feedback in one line each
- **Appendix**: `evaluations/00-design-evaluation.md`, `tasks/T001-add-oauth-providers.md` (as read for the run; the originals stay in the state branch history at the source commit)

This file is a **shape** reference; the agent should fill in real text from the user’s project, not copy this example.
