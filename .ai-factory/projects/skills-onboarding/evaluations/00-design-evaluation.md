# Design Doc Evaluation Report

## Metadata

| Field | Value |
|---|---|
| **Design Doc** | `.ai-factory/projects/skills-onboarding/00-design.md` (revision 2) |
| **Evaluator** | factory-evaluator |
| **Date** | 2026-11-19 |
| **Verdict** | ready-for-planning |

## Alignment Check

The goal hasn't changed. Installation moves to each tool's native mechanism: a Claude Code marketplace, and a user-level copy into `~/.cursor/` for Cursor. A `factory-setup` skill replaces hand-editing `config.md`. A target repo holds only `config.md`, two `.gitkeep` files and four ignore lines. The Verifier fails when Test or Lint is not configured. The four human decisions are taken as given:
- templates are inlined into subagent prompts;
- the Cursor project-level copy is dropped;
- the `.cursor-plugin/` manifests are deferred;
- team pinning becomes a README snippet.

Alignment is above 90%.

## Executive Summary

Revision 2 makes targeted changes to the previous doc:
- **"Set up" is a fixed set**: `config.md` exists, Test and Lint are configured, and both `.gitkeep` files exist. Optional fields and declined integrations never count as gaps.
- **Apply-without-review mode**: any branch that would ask the human leaves its fields unfilled and states the reason. A non-git directory or the home directory aborts.
- **Templates**: the skill reads its own template. It pastes `design.md` into the Architect prompt and `epic.md`/`task.md` into the Planner prompt. It applies `evaluation.md`, `review.md` and `verify.md` itself when it saves the returned reports. No agent reads a template file.
- **`check.sh`**: now also checks the Verifier's Required flags and rejects an unconditional `skipped` rule.
- **Cuts**: the Cursor project-level copy, the `.cursor-plugin/` manifests and setup step 7 (team pinning) are removed.
- **New evals**: `already-set-up` (revised), `polyglot-no-runner`, `partial-lint-gap` with anchored regexes, and `confirmation-gate`.

## Resolution status

| # | Prior finding | Status | Evidence |
|---|---|---|---|
| 1 | Idempotency vs. gap definition | **resolved** | Goal 4, Procedure steps 2–3 and the `already-set-up` fixture (unfilled optional rows, no `.gitignore` lines, Write/Edit `max: 0`) all use the same definition. |
| 2 | Cursor project-level copy vs. Goals 3/8 | **resolved** | Non-Goals and the Cursor flow (copy is user-level only, `rm` before `cp`). Customization step 2 puts Cursor overrides at project level. Eject is clearly outside the install path. |
| 3 | Apply-without-asking vs. ask branches | **resolved** | Step 1 aborts; step 5 defines the mode; the edge-case preamble applies it; step 7 never runs the smoke test in this mode; `polyglot-no-runner` eval. |
| 4 | Template-by-absolute-path | **resolved** | Inlining by human decision. The Template contract, the Template table and the Architect/Planner "stop if no template" rule all agree. The acceptance run checks that the Design Doc follows `design.md`'s headings in both tools. |
| 5 | Weak Verifier contract check | **resolved** (narrow) | Required-flag equality and the unconditional-skip regex were added. The regex only matches the wording of line 71 (see note). |
| 6 | `.cursor-plugin/` manifests | **resolved** | Moved to Non-Goals. They remain only in the research table, which is correct. |
| 7 | Team pinning in setup | **resolved** | Data Model 4 is a README snippet. Goal 3 excludes tool settings, the Non-Goals say so, and setup has no pinning step. |
| P | Planner notes | **resolved** | Covered: self-excluding grep, anchored graders, `confirmation-gate`, evals kept in `plugin/evals/` with justification, stale-agent Troubleshooting, Test Required for repos without tests, Lint needs `claude`, the SHA-per-commit wording, validating both `.` and `./plugin`, the copy deleting old files first, and how `factory-design` uses `evaluation.md`. |
| I | Impact Map fixes | **resolved** | Covered: 4 skill directories, README lines 420 and 460 (both confirmed in the README), the conditional `LICENSE` row, and the dogfood `config.md` as the last step. |

### Codebase cross-check of the inlined-template strategy

I grepped `.ai-factory/templates`, `templates/` and "template" across the repo, excluding `.ai-factory/projects/`. The hits in `.ai-factory/framework/` are:
- **`factory-architect.md`**: lines 21 and 33 (lines 34, 42 and 43 say "template" generically and still work with an inlined template). Covered.
- **`factory-planner.md`**: lines 41–43 and 122. Covered.
- **`factory-reviewer.md`**: line 55. Covered.
- **`factory-verifier.md`**: line 53. Covered.
- **`factory-evaluator.md`**: no template reference. Matches "Evaluator gets no template".
- **`factory-design/SKILL.md`**: lines 25, 30 and 84. Covered. It has never mentioned `evaluation.md`; the new "format when persisting" rule is explicitly specified.
- **`factory-plan/SKILL.md`**: lines 30, 31, 77 and 78. Covered.
- **`factory-build/SKILL.md`**: lines 54–55 are covered. Lines 40 and 75 ("task template", "template conventions") have no path and are harmless.
- **`factory-archive/SKILL.md`**: lines 13, 30 and 75 (templates) and lines 32 and 69 (examples). Covered.
- **`factory-archive/reference.md`**: lines 3 and 12. Covered.

All remaining hits are in deleted adapters (`.claude/` and `.cursor/`), `sync.sh`, `sync-check.yml`, the examples evaluation, or `README.md`. No consumer outside the File Impact Map exists. The new `check.sh` rule "no agent file mentions `templates/`" does not conflict with the revised Architect text ("follow the template in your prompt").

## Critical Vulnerabilities & Blind Spots

No critical or high findings. One medium inconsistency was introduced by the revision.

### Re-detect scope contradicts "never changes a value a human wrote"

- **Severity**: medium
- **Origin**: Procedure step 4 ("Scope: every field … on 're-detect'") and step 6 ("edit only the proposed rows"), against Goal 4 and the Risks row "filled values never changed".
- **Description**: On "re-detect", step 4 proposes every field, including Test and Lint values a human already filled. Step 6 then writes the proposed rows. Combined with apply-without-review mode, "re-detect and apply" silently overwrites human-written commands. Step 3's hint, "ask me to re-detect to fill them", suggests re-detect was meant to fill unfilled fields only.
- **Impact**: the Planner could write Gherkin that allows overwriting, and no eval covers re-detect. The fix is one sentence: re-detect covers unfilled fields and absent `.gitignore` lines only, filled values are shown as "kept", and they change only through an explicit "change something" edit.

## Trade-off Analysis

| Decision | What You Gain | What You Sacrifice |
|---|---|---|
| Inline templates into Architect/Planner prompts | Works the same in both tools: no path resolution, no subagent reads outside the workspace | A few KB per invocation. An Architect or Planner invoked directly has no template and stops (accepted as a low risk). |
| Skill applies `review.md` / `verify.md` itself | Reviewer and Verifier carry no template dependency | Once the template reference is removed, these agents have only a thin output spec ("end with verdict"). The skill can only shape a report from data the agent actually returned (see notes). |
| "Set up" = required set only | Real idempotency; no repeated proposals full of unfilled optional fields | Unfilled optional fields stay unfilled until the user asks to re-detect. |
| Cursor overrides at project level only | Upgrades cannot clobber overrides | User-level Cursor customization is impossible without editing files that the next copy replaces. This is documented. |

## Alternative Approaches

### For: Re-detect scope

Change step 4's scope line to: "on 're-detect': every *unfilled* field and absent `.gitignore` line; filled rows appear in the table as `kept` and are changed only by an explicit human edit." Optionally add a `redetect-keeps-values` eval that reuses the `partial-lint-gap` anchored-regex pattern.

## Hard Questions

1. On "re-detect", may setup propose replacing a filled **Test** or **Lint** value, or only fill unfilled rows (yes or no)?
2. Once the template references are gone, must the Reviewer and Verifier still return a fixed minimum set of fields? For the Verifier: command, status, exit code and an output excerpt per check. For the Reviewer: per-scenario status, and findings with severity and location. Without them, can the skill fill `review.md`/`verify.md` without inventing content?

## Notes for the Planner (implementation-level)

- **Reviewer/Verifier output floor**: when dropping the template references (`factory-reviewer.md` line 55, `factory-verifier.md` line 53), keep a short inline list of the fields the agent must return, so the skill's reshaping into `review.md`/`verify.md` has the data it needs. `verify.md`'s Verdict comment ("pass if ALL checks are pass or skipped") stays correct, because a not-configured Required check has status `fail`.
- **"All four stage skills"** (API Surface, Subagent selection contract): only `factory-design`, `factory-plan` and `factory-build` have an "Invoking subagents" section today. `factory-archive` invokes no subagents. Don't create a task to add one.
- **README row**: lines 177 and 210 contain `.ai-factory/templates/` text in the Stage 2 and Archiving sections, which the listed README sections don't cover. The stage-skill links (lines 177, 185 and 199) must be repointed to `plugin/skills/...`, not just removed. `check.sh`'s stale-path grep would catch any misses in CI, but say it in the task.
- **Unconditional-skip regex** (`missing from config.*skipped`): it would not catch line 47's wording ("If a config key is empty or marked `none`, skip that check"). Both lines are being rewritten, so this is a regression guard only. Consider matching any line with `skip` that lacks "optional".
- **Goal 1 count**: the confirmation reply that Goal 5 requires is arguably a sixth action. Treat the count as approximate, or say confirmations are not counted, so that no acceptance test counts them literally.
- **Empty repo**: `git log -20` fails in a repo with no commits. Treat that as "no commit history". A rendered all-placeholder `config.md` counts as absent on the next run, which is consistent with the definition.
- **"No out-of-workspace read is needed"** is slightly overstated for Cursor. The main agent reads `~/.cursor/skills/<skill>/templates/*.md`, which is the documented supporting-file mechanism. The acceptance run already covers it.

## Verdict

**Verdict**: ready-for-planning

**Reasoning**: Every prior finding, Planner note and Impact Map fix holds against the text and the codebase. The "already set up" definition matches the procedure, Goal 4 and the `already-set-up` eval. The apply-without-review rules cover every ask branch, the abort and the smoke run. The inlined-template strategy covers every template reference the grep found in agents and skills, and no consumer outside the Impact Map exists. The one new inconsistency (re-detect scope) is a one-sentence fix that the Planner can absorb into the `factory-setup` task's Gherkin. Everything else is implementation-level.

**Required revisions** (absorb in planning; no re-evaluation needed):
1. Limit "re-detect" to unfilled fields and absent `.gitignore` lines; filled values change only through an explicit human edit.
