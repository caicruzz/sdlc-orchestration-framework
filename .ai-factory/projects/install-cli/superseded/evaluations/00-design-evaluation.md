# Design Doc Evaluation Report

## Metadata

| Field | Value |
|---|---|
| **Design Doc** | `.ai-factory/projects/install-cli/00-design.md` (revision 3.1) |
| **Evaluator** | factory-evaluator |
| **Date** | 2026-11-19 |
| **Verdict** | ready-for-planning (the Planner must settle the notes below as explicit decisions) |

## Alignment Check

Alignment is well above the 90% bar, and revision 3.1 leaves the architecture unchanged.

- **What it is:** a zero-dependency Node 24+ ESM CLI on npm, published with trusted publishing and provenance and run as `npx soloaifactory@<version>`.
- **What a target repo holds:** only what it owns (`overrides/`, `config.md`), the generated adapters, templates and `.gitkeep` files, managed git blocks, and a committed TSV lock.
- **What the lock does:** it pins the version and a build digest, hash-tracks every generated file, and holds override baselines that only `ack` writes.
- **Source repo:** `sync.sh` is deleted, and this repo becomes a self-host install of itself.

These are human decisions and are not treated as defects: Node/npm, the framework shipped in the package, project scope only, the overrides layer, ack-only baselines and native Windows support.

I checked the doc's claims against the tree, and they hold:
- `sync.sh` header lines 7-9 and its awk renderers match the doc.
- In `factory-build/SKILL.md`, the Step C table is at lines 62-67, in the order the doc assumes (`pass|pass`, `revisions-needed|anything`, `anything|fail`, mixed).
- The Verifier text is at lines 42, 47, 62-63 and 71.
- The config template labels are **Test**/**Lint** Required and **Type check**/**Build** Optional.
- There are 22 committed adapters (6 agents + 5 skill files, for each of the two tools).
- Both `.gitkeep` files are empty, so step 4 adopts them via row 10.
- Every framework `description` is a block scalar, so the new plain-scalar ban on `: ` and ` #` does not break the framework contract test.
- `sync.sh`, `.ai-factory/framework` and `.ai-factory/examples` are referenced only in files the File Impact Map covers.
- CI is the single `.github/workflows/sync-check.yml`.

## Executive Summary

Revision 3.1 is a targeted revision of revision 3. It adds:
- A junk-file ignore list, a narrow definition of "generated directory", and informational (exit 0) unmanaged files.
- `install --relock`, a two-sided lenient parse of a conflicted lock that keeps agreeing and one-sided baselines.
- Frontmatter baselines keyed on each overridden key's line span, plus per-tool `cursor.model`/`claude.model`.
- A digest over `framework/`, `src/` and `bin/` with POSIX paths, a cross-OS equality job, two digest-mismatch messages and `--allow-unreleased`.
- Self-host sentinels (`0.0.0-self`/`self`), a source-repo refusal and a binding restructuring order.
- A bare command that prints usage and exits 2.
- Cross-platform rules: content-based text detection, CRLF normalization of every input, lowercase unit names with case-collision rejection, a no-symlink policy, exec-bit preservation, and `realpathSync.native` with case-folding on win32.
- A frontmatter contract for every agent and skill.
- Step C row precedence.
- A first-publish path through `release.yml` with an environment token, a reviewer-gated `npm-publish` environment and least-privilege permissions.
- Exit 7 for a held mutex.
- Frozen lock `version` line and exit-code meanings.

## Status of Revision-3 Required Revisions, F-findings and Lower-Severity Items

| Item | Status | Verification notes |
|---|---|---|
| RR1 / F1 junk files, "generated directory" | **Resolved** | The nine-pattern list is applied to overrides, the framework scan and generated directories. The definition is exact (`.ai-factory/templates/` plus each generated `.<tool>/skills/<name>/`). Unmanaged files and leftovers are `info` lines and never change the exit code. There are packaging and contract tests. Residue: `.gitkeep`/`README.md` in `overrides/` and macOS `._*` (Planner note P8) |
| RR2 / F2 lock conflicts | **Resolved in substance, with gaps** | `--relock` keeps agreeing and one-sided `override` records, untracks the ones the sides disagree on, never infers from disk, handles diff3 and hand-merged duplicates, and the error message names it with `--target`. New gaps in its `gen` and version rules: N1 |
| RR3 / F3 frontmatter granularity, per-tool model | **Resolved** | The digest covers sorted `<key>\t<span hash or ->` lines. `cursor.model`/`claude.model` map to the `model` span. Precedence is `<tool>.model` > `model` > base, dotted keys are never emitted, and appends are deliberately whole-file. Goal 4 (v) tests it |
| RR4 / F4 digest scope, OS dependence, looping advice | **Resolved** | Scope is `framework/`, `src/`, `bin/`, with POSIX paths built by the CLI, a committed `-text` fixture digest and a `digest-equal` job. The checkout and packaged messages never echo the user's command. A same-version re-pin needs `--allow-unreleased`. No loop: the packaged-CLI remedy re-pins to the published build. Naming nit in P9 |
| RR5 / F5 self-host | **Resolved** | The 4-step binding order deletes the legacy adapters before the first install. The legacy marker maps to row 11. Constant sentinels mean framework PRs touch only `gen` lines. There is a source-repo refusal with `npm run check` advice, and golden parity renders `golden-sources/`. Nit: the step for `config.md` is implicit (P9) |
| RR6 / F6 bare command | **Resolved** | Prints usage on stderr and exits 2 in the Process model, Commands, Exit codes and tests |
| RR7 / F7 cross-platform | **Mostly resolved** | Case, symlinks, CRLF inputs, content-based text detection, `text=auto eol=lf`, the Windows-safe CI step, the review hint without process substitution and win32 realpath case-folding are all specified and tested. New gaps in exec-bit handling (N4) and in case-only renames (N5). Symlink coverage and text-rule divergence are minor (P6, P7) |
| RR8 / F8 frontmatter contract | **Resolved, new over-strictness** | `name` must equal the stem, `description` is required, `tools` with `readonly: true` is exit 6, plain scalars may not contain `: ` or ` #`, and a contract test parses the framework. But the subset now rejects common, valid tool frontmatter in user-authored units (N3) |
| RR9 / F9 Step C order | **Resolved** | The row comes first after `pass|pass`, an override sentence follows the table, and the contract test asserts it is the second data row. Verified against SKILL.md lines 62-67 |
| RR10 / F10 release | **Resolved** | The first publish comes from `release.yml` with an environment-secret token, and provenance comes from OIDC. Then trusted publishing pinned to `npm-publish`, which has required reviewers. Workflow-level `contents: read`, `id-token` only on `publish`, and the CHANGELOG check happens before publish. OQ1 is cleaned up |
| Lower: `.factory-backup/` ignore line | Resolved | Uninstall §3 and Data Model §2 |
| Lower: managed git block edits | Resolved | Stated as the one exception to Goal 3, with a visible plan line |
| Lower: frozen fields | Resolved | `version<TAB><semver>` and exit codes 0–7 are frozen; changing them is a major version |
| Lower: npx caching claims, `--yes` | Resolved | `--yes --prefer-offline` is in every printed pinned command; `@latest` lines resolve fresh |
| Lower: exit 4 transient vs permanent | Resolved | Exit 7 |
| Lower: `node --test` patterns | Resolved | Explicit glob, which also works through cmd.exe |
| Lower: File Impact Map omissions | Resolved | `examples/.../00-design-evaluation.md` path, `LICENSE`, golden and digest fixtures, new tests |
| Lower: `show` path joining | Resolved | Looked up in the packaged file list only |
| Lower: devDependency semantics | Resolved | Compares the declared spec, never `node_modules` |
| Lower: lock deletion loses `targets` | Resolved for the message; see N2 | The message and `--relock` carry targets, but plain `install` still defaults to `all` |
| Lower: `status --remote` proxy/registry | Resolved | |
| Lower: unknown kinds across downgrade | Resolved | Stated and accepted |
| Lower: unknown-kind ordering contradiction | Resolved | One rule |
| Hard Questions 1–5 | Answered | All five have concrete answers in the doc |

## Critical Vulnerabilities & Blind Spots

There are no critical or high findings. Everything below is medium or lower, and each item can be settled as a localized rule during planning.

### N1. `--relock` mis-handles generated files that match a side, and allows an unflagged downgrade

- **Severity**: medium
- **Origin**: Lock failure and recovery, `--relock` steps 2 and 4
- **Description**:
  - **Composed paths that match a side are blocked.** Step 4 rebuilds `gen` "as an install": composed paths get the no-lock rows 9–12. But paths that are no longer composed are removed when the disk matches *either side's* recorded hash. The two halves are inconsistent.
  - The common merge goes like this. Branch A edits an override and runs `sync`. Branch B upgrades. The adapter conflicts in git, and the user resolves it by taking one side, so the disk now equals that side's recorded hash. Relock computes `exp` (new version plus A's override). Disk ≠ `exp`, so the file falls to row 11: blocked, and `--force` is needed. That file is provably pristine, earlier output, yet the user is pushed to `--force` and gets backups of generated files.
  - **Relock with the older side's CLI is a downgrade.** Step 2 accepts a CLI matching *either* side. If A is at 0.2.0 and B at 0.1.0, running relock with 0.1.0 is valid. A's 0.2.0 adapters then become row-11 blocks, and with `--force` the repo is silently downgraded to 0.1.0 without `--allow-downgrade`. If N1's first fix is applied, the downgrade would not even need `--force`.
  - **Wording.** Goal 4 (vi) says "no other override changes state". When the sides' versions differ, a one-sided record acked on the older version correctly becomes stale under the newer one. The wording should cover that.
- **Impact**: The most common post-conflict path produces avoidable `--force` runs, and the downgrade guard of Goal 10 can be bypassed through relock.

### N2. `install` defaults to `--target all` even when a lock exists

- **Severity**: medium
- **Origin**: Flags (`--target` default "install: `all`"); Goal 2; Lock failure and recovery ("on a parseable lock `--relock` behaves exactly like `install`"; relock targets default to the union of the sides)
- **Description**:
  - On a cursor-only install, a second plain `install` (the documented same-version reconcile) adds `.claude/`. That contradicts Goal 2's "changes nothing".
  - `--relock` on a *parseable* lock is defined as plain `install`, so it also expands to `all`. Yet `--relock` on a conflicted lock defaults to the lock's targets. The doc took care to put `--target` in the recovery message for exactly this reason.
- **Impact**: Unexpected adapters for a tool the repo opted out of, and a mismatch between the idempotency test and the documented semantics.

### N3. The YAML subset rejects valid, common frontmatter in user-authored agents and skills

- **Severity**: medium
- **Origin**: Overrides composition, frontmatter contract ("any other key is passed through verbatim", "parsed by the same subset reader"); Data Model §5 (no flow collections, no nested mappings, no plain scalars starting with `[`)
- **Description**:
  - The contract claims unknown keys pass through verbatim, but the grammar only admits scalars. All of these are valid in Claude Code or Cursor frontmatter and appear in community skills and agents:
    - `argument-hint: [pr-number]` (a flow sequence);
    - `allowed-tools:` or `tools:` written as a block sequence (`- Read`);
    - a `metadata:` or `hooks:` mapping.
  - Each is exit 6 for every command, including `status` in CI, the moment a user adds a new or replacement unit that uses them.
- **Impact**: The overrides layer, the only supported customization path, refuses legitimate content with no workaround other than rewriting the frontmatter.

### N4. Exec bits are not stable across Windows authors and mode-less file systems

- **Severity**: medium
- **Origin**: Cross-platform rules (Exec bits); Status ("exec-bit mismatch: run sync" is an attention item); Testing (exec bits checked only in the `npm pack` tarball)
- **Description**:
  - **Windows authors.** On win32 the CLI does not write modes, and git with `core.fileMode=false` adds new files as `100644`. A generated script that should be executable, first added and committed by a Windows teammate, checks out without `+x` on Linux. Linux CI `status` then exits 3 until a POSIX user runs `sync` and commits a mode change.
  - **File systems without mode support** (WSL `/mnt/c` without metadata, exFAT, some network shares) report every file as executable, or ignore `chmod`. Exec-bit mismatch becomes a permanent attention item that `sync` cannot fix.
  - **Untested extraction step.** The packaging test checks the tarball, but the CLI reads modes from the npx-extracted package, and that step is not asserted.
  - **Scope.** Today no framework file is executable, so the exposure is override-provided scripts and future skills.
- **Impact**: Recurring or permanent exit 3 in mixed-OS teams. That is the "teams learn to ignore 3" failure mode F1 was meant to remove.

### N5. A case-only rename with unchanged content is a no-op, and git will not commit it on case-insensitive file systems

- **Severity**: medium (low likelihood)
- **Origin**: Cross-platform rules (Case); decision table
- **Description**:
  - When upstream only changes a file's case, `exp == lock` for the paired entry, so it falls to row 1 (skip). The "unlink + rename" write never happens, the on-disk name keeps the old case, and the lock records the new case.
  - Even when the CLI does rename, git with `core.ignorecase=true` does not stage a case-only rename. A Linux clone then sees the new lock path missing (row 5, exit 3) and the old path as an unmanaged file.
- **Impact**: macOS and Windows developers see a clean `sync`, while Linux CI stays red.

### Lower-severity items (notes for the Planner)

- **P6 Symlink coverage.** The `lstat` list does not name `.gitignore`, `.gitattributes` or `config.md`, which the CLI writes; temp + rename would silently replace a symlink there. Add them. A symlinked *file* under `core.symlinks=false` checks out as an ordinary text file and cannot be detected without git; document this.
- **P7 Text rule vs git `text=auto`.** git treats a file as binary only if it has a NUL in the first 8000 bytes. The CLI also requires valid UTF-8. A Latin-1 text file with CRLF, or a file whose NUL comes after 8000 bytes, is binary to the CLI and text to git. git then normalizes its line endings on commit, so clones see a hash mismatch (row 4). Either mirror git's rule exactly or accept this and document it. Separately, `.bat`/`.cmd` skill files get LF endings; document it.
- **P8 Overrides hygiene.** `overrides/agents/.gitkeep` (common for keeping empty directories) and `overrides/README.md` are exit 6. Add `.gitkeep` to the ignore list for `overrides/`, and decide whether a top-level `README.md` is allowed. Add `._*` (AppleDouble), which `npm pack` already excludes, to the junk list, so self-host output on macOS external volumes still matches the tarball.
- **P9 Consistency nits:**
  - **Exit precedence.** Status precedence lists 5 (no lock) before 4 (symlink), while the Process model runs the symlink check before reading the lock. Pick one order.
  - **Status list.** Row 8 (lock out of date) is missing from the Status list.
  - **`sync --check` scope.** Say whether it also reports override attention items under the "one rule".
  - **Uninstall in the source repo.** Say whether the `framework self` / `name: soloaifactory` refusal applies to `uninstall`, which has no version gate.
  - **Self-host ack hints.** `ack` in self-host records `0.0.0-self`, so stale-review hints would print `npx soloaifactory@0.0.0-self`. Suppress them in self-host.
  - **`--allow-unreleased` naming.** It is also the flag a published-CLI user passes to return to the released build. Consider wording the warning for that case, or renaming the flag (`--repin`).
  - **`--set` with an existing config.** `--set` is silently ignored when `config.md` exists; warn.
  - **`.gitattributes` order.** The repo `.gitattributes` must place `test/fixtures/digest-package/** -text` after `test/** text=auto eol=lf`.
  - **`config.md` in the restructuring.** State whether `.ai-factory/config.md` is hand-written in step 2 or rendered by the step-4 install.
  - **Frontmatter stale message.** A frontmatter override goes stale when the user changes its key set, but the stale message says "base changed since your ack". Word that case separately.
- **P10 Release.** The "reachable from `main`" check needs `fetch-depth: 0`. Required reviewers on environments need a public repo or a paid plan for private repos; confirm before relying on it.

## Trade-off Analysis

| Decision | What You Gain | What You Sacrifice |
|---|---|---|
| `--relock` with sides and no 3-way base | Non-destructive recovery, and drift is never cleared silently | When both sides changed one record (e.g. A re-acked, B untouched), it is untracked, even though diff3 could show that only A changed it. Every such conflict needs a re-ack |
| Key-span frontmatter baselines | A `model:` override survives body edits | A second line-span parser to keep correct for block scalars. Changing the override's own key set also makes it stale |
| Strict YAML subset for all frontmatter | One small, auditable parser and precise errors | Legitimate tool frontmatter in user units is rejected (N3) |
| Exec-bit preservation, not tracked on win32 | Skill scripts stay runnable on POSIX | Mode drift between Windows authors and POSIX CI becomes an attention item (N4) |
| Self-host sentinels | Framework PRs never conflict on version/digest lines | The riskiest paths (the version gate and `upgrade`) are never dogfooded in this repo. Only the fake-package tests cover them |
| Digest over `src/` and `bin/` | Any code change at the same version is detected | Every patch to CLI internals forces a version bump before contributors can test against shared repos (accepted through `--allow-unreleased`) |
| Exit 7 for a held mutex | Scripts can retry safely | One more frozen code. A reused PID keeps returning 7 until the directory is deleted by hand |
| Junk list instead of "ignore all dotfiles" | Precise and predictable | Junk names not on the list (`._*`, `.gitkeep` in overrides) still break the layout (P8) |

## Alternative Approaches

### For N1 (relock `gen` and version rules)

- In relock, treat a composed path whose disk hash equals *either* side's recorded hash as that side's lock hash. It then becomes row 1 or row 2 (update), never row 11. This matches the existing removal rule.
- Require the running CLI to match the **newest** side's version (and digest). A match with an older side is exit 4 with the existing downgrade message, unless `--allow-downgrade` is given.
- Optionally ship `-merge` (binary merge) for the adapter and template patterns in the managed `.gitattributes` block. git then never writes hybrid generated files; a conflict leaves one side's exact bytes, which the first rule turns into a clean update.

### For N2 (install targets)

When a lock exists, `install` defaults to the lock's `targets`; `all` applies only to a fresh install. `--target` still widens or shrinks explicitly.

### For N3 (frontmatter strictness)

- Parse strictly only the keys the CLI interprets (`name`, `description`, `model`, `cursor.model`, `claude.model`, `readonly`, `shell`, `tools`).
- Treat every other key as an opaque line span (the key line plus its indented or `- ` continuation lines, and a flow value on one line) and pass it through byte for byte.
- `.frontmatter.yml` stays fully strict.

### For N4 (exec bits)

- Before comparing modes, probe whether the target file system honours `chmod`: write a temp file, `chmod` it and re-`stat` it. If it does not, treat the target like win32 (modes not tracked).
- On win32, when a planned add or update has an expected exec bit, print `git update-index --chmod=+x <path>` in the plan.
- Optionally downgrade exec-bit mismatch to `info` in `status`, and keep it as attention only in `sync --check`.
- Extend the ubuntu `npx ./*.tgz` smoke test to assert the exec bit on a generated script after extraction.

### For N5 (case-only renames)

- Compare the actual on-disk name, found by reading the parent directory, with the expected case.
- Force a write (unlink + rename) when only the case differs, and print a hint to commit it with `git mv`.

## Hard Questions

1. When `--relock` runs with the CLI matching the older side of a conflict, should it refuse (exit 4 unless `--allow-downgrade`), or is regenerating the merged repo at the older version acceptable?
2. In relock, is a composed file whose disk bytes equal one side's recorded hash pristine (update without `--force`), or an edit (row 11)?
3. Should a re-run of `install` on an existing lock default to the lock's `targets` (preserving Goal 2 for cursor-only and claude-only repos), or to `all`?
4. Must user-authored replacement and new agents and skills be able to use YAML sequences, flow values or mappings for keys the CLI does not interpret (`allowed-tools`, `argument-hint`, `hooks`), or is exit 6 on them an accepted v1 limitation that the README documents?
5. When a Windows teammate commits a new generated executable as `100644`, which is the intended outcome on Linux CI: exit 3 until a POSIX user runs `sync`, or a non-blocking `info` line?

## Verdict

**Verdict**: ready-for-planning

**Reasoning**: Every revision-3 required revision is resolved in the doc, not just mentioned:
- F1, F3, F4, F5, F6, F8, F9 and F10 are resolved as claimed, and F2 and F7 are resolved in substance.
- Every lower-severity item is addressed.
- I checked the codebase-facing claims (Step C row order, Verifier text, template labels, framework frontmatter shape, the 22 adapters, empty `.gitkeep` files, the reference sites in the File Impact Map) and they are accurate.
- Exit codes, the version table, the decision table, the File Impact Map and the test plan are consistent, apart from the P9 nits.

The new issues are localized rule refinements, not architectural defects, and none of them causes data loss:
- **N1 (relock):** at worst, users run `--force` with backups, and relock allows an explicit-but-unflagged downgrade.
- **N2 (`--target` default):** one default to change.
- **N3 (subset strictness):** the fix is to make unknown keys opaque.
- **N4 (exec bits):** probe and hint rules.
- **N5 (case-only renames):** a forced write.

The Planner can safely turn each one into a task or acceptance criterion. Another design round is not needed.

**Notes for the Planner** (settle these as explicit decisions in the task files; the defaults below are recommended):
1. N1: in relock, disk == either side's hash counts as pristine; the CLI must match the newest side, otherwise exit 4 unless `--allow-downgrade`; reword Goal 4 (vi). Optionally add `-merge` to generated-file patterns in `.gitattributes`.
2. N2: when a lock exists, `install --target` defaults to the lock's `targets`.
3. N3: unknown frontmatter keys are opaque line spans; strict parsing only for interpreted keys and `.frontmatter.yml`.
4. N4: probe for mode support; give a `git update-index --chmod=+x` hint on win32; assert exec bits after npx extraction in the smoke test.
5. N5: force a write on a case-only difference and hint `git mv`.
6. P6–P10 as listed: symlink coverage for `.gitignore`/`.gitattributes`/`config.md`; text-rule alignment with git or documentation of the gap; `.gitkeep`/`._*` in the ignore lists; exit-precedence order; row 8 in status; `sync --check` scope; uninstall in the source repo; self-host ack hints; `--set` warning; `.gitattributes` rule order; `config.md` restructuring step; stale-message wording; `fetch-depth: 0`; plan support for environment reviewers.
