# SDLC archive skill: example outputs

Illustrative fragments for **`dependency-graph.md`** and **`project-summary.md`**, based on **`.sdlc/examples/oauth2/`**. That example has no `01-epic.md`; a real run with an epic copies the **## Task dependency graph** section from `01-epic.md` verbatim into `dependency-graph.md`.

## Example: dependency-graph.md (synthetic, when epic is missing)

When `01-epic.md` is absent, the skill may emit a short stub plus any graph recovered from the task list. A minimal file might start like:

- Title line: `# OAuth2 (example) — no epic on disk`
- Body: a short note that `01-epic.md` was not found, plus optional mermaid if inferred from task IDs.

With a real epic present, the file should include the full **## Task dependency graph** content from the epic: prerequisite paragraph, mermaid `flowchart` block, and **### Legend** (per **`.sdlc/templates/epic.md`**).

## Example: project-summary.md (structure only)

- **Metadata table**: slug, archive ISO timestamp, line stating `00-tdd.md` was left unchanged.
- **Link to graph**: relative path from **`.sdlc/projects/<slug>/project-summary.md`** to **`.sdlc/archive/<slug>/<ts>/dependency-graph.md`** (e.g. `../../archive/<slug>/<ts>/dependency-graph.md`).
- **Epic (text)**: copy or shorten title, summary, and task list table from `01-epic.md` (no mermaid in this file).
- **TDD evaluation** (from `evaluations/`): e.g. for `00-tdd-evaluation.md` — **verdict** `needs-revision`, **date** `2026-04-21`, bullets on CSRF/state handling, email collision, and other critical findings.
- **Per task** (from `tasks/T*.md`): e.g. **T001** — title “Add OAuth Provider Infrastructure”, one-line objective, Gherkin scenario titles only, review/verify summaries from the task file or sidecar files.
- **Appendix**: `evaluations/00-tdd-evaluation.md`, `tasks/T001-add-oauth-providers.md` (as read for the run).

This file is a **shape** reference; the agent should fill in real text from the user’s project, not copy this example.
