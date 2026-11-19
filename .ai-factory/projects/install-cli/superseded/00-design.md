# Design Doc

## Metadata

| Field | Value |
|---|---|
| **Project** | soloAIfactory |
| **Feature** | install-cli: a Node CLI, published on npm, to install, onboard, sync, upgrade and uninstall soloAIfactory in another repository (project scope) |
| **Author** | factory-architect |
| **Status** | draft |
| **Created** | 2026-11-18 (revision 2: 2026-11-18; revision 3: 2026-11-18; revision 3.1: 2026-11-18, a targeted revision after the revision-3 evaluation in `evaluations/00-design-evaluation.md` and human decisions; see Revision history at the end) |

## Problem Statement

soloAIfactory only works once its files are in the target repository, and today getting them there is a manual, lossy, one-way process. The README Quick Start reads:

```bash
cp -r .ai-factory/ /path/to/your/project/.ai-factory/
/path/to/your/project/.ai-factory/sync.sh            # writes .cursor/ and .claude/
# or: .ai-factory/sync.sh --target cursor | --target claude
```

followed by hand-editing `.ai-factory/config.md`.

That flow has these concrete problems, all checked against the current tree:

1. **Every target carries a vendored copy of the framework, and the source repo and an install are the same tree.** `.ai-factory/` in this repo holds the canonical sources (`framework/`, `templates/`, `sync.sh`) together with things that should never ship: `.ai-factory/examples/oauth2/**` (reference artifacts) and `.ai-factory/config.md`, which is both the blank template users fill in and, in principle, this repo's own config (today still blank, so this repo does not dogfood its own Verifier). A `cp -r` copies examples and whatever state `config.md` is in, and leaves each target with its own copy of `framework/` and `sync.sh` that must later be replaced file by file.
2. **Git hygiene is manual.** The target repo needs `.gitkeep` files in `projects/` and `archive/` plus these ignore rules, which live only in this repo's `.gitignore`:
   ```gitignore
   .ai-factory/projects/*
   !.ai-factory/projects/.gitkeep

   .ai-factory/archive/*
   !.ai-factory/archive/.gitkeep
   ```
   `cp -r` also copies any local `projects/*` and `archive/*` content from the source checkout.
3. **There is no upgrade path, and the customization model makes one hard.** Nothing records which framework version was installed. The README ("Customizing for Your Project") tells users to customize by **editing upstream-owned files in place**: `framework/agents/*.md` (then re-run `sync.sh`) and `templates/*.md`. Any upgrade must then tell user edits from upstream edits file by file and merge them. Re-copying a newer `.ai-factory/` silently overwrites those changes; not re-copying leaves the install stale.
4. **There is no uninstall.** Removing the factory means working out by hand which files in `.cursor/` and `.claude/` are generated. `sync.sh` knows this through its marker, but nothing exposes it.
5. **Config is entirely manual, and an unfilled config fails silently.** The Verifier runs whatever commands `config.md` lists, and its prompt says "If a config key is empty or marked `none`, skip that check". It also looks up keys named `test_command` / `lint_command`, while the config template uses the labels **Test** / **Lint**. A user who skips the config step gets a Verifier that skips everything and never fails. Most of those values can be read from `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml` and similar files.
6. **There is no collision safety.** `sync.sh` overwrites same-named `factory-*` agents and skill files even when they carry no generated marker (`sync.sh` header: "Same-named factory-* agents and skill files are overwritten"). A target that already has its own `.claude/agents/factory-coder.md` loses it without warning.

The project has no users yet (no git tags, no releases, nothing on npm), so this is the right time to change how the framework is distributed, replace in-place customization with a model that upgrades cleanly, and set up versioning before any install exists in the wild. No backwards compatibility with the current layout is needed.

**Direction of revision 3 (human decision):** the CLI is a zero-dependency **Node** program published to **npm** with provenance and run as `npx soloaifactory@<version> <command>`. The npm package carries the framework, so a target repo keeps only what it owns or what must be on disk for Cursor and Claude Code to load. `sync.sh` is folded into the CLI and deleted.

**Scope of v1:** project-level installs only (everything lives in the target repository). User-level installs are deferred; see Non-Goals.

## Goals

1. **One-command onboarding.** From inside any git repository, on a machine with Node 24 or newer, `npx soloaifactory@<version> install` produces a working project-level soloAIfactory: generated `.cursor/` and/or `.claude/` adapters, generated `.ai-factory/templates/`, `projects/` and `archive/` scaffolding, managed `.gitignore` and `.gitattributes` blocks, a prefilled `.ai-factory/config.md` and the committed lock. Success criteria: (a) on the `node-npm`, `node-pnpm-ts`, `python-uv`, `python-poetry`, `go` and `rust` fixtures, a non-interactive install fills **Test** and **Lint** with non-placeholder commands and exits 0; (b) on `node-no-lint`, **Lint** stays a placeholder, the install warns naming **Lint** and exits 3, `status` exits 3, and the Verifier contract (Goal 9) turns the gap into a `fail`; (c) on `node-npm-init` (the `npm init` placeholder test script), **Test** stays a placeholder and is warned about; (d) on `polyglot-two-signals` (Python with pytest plus Node with a real test script), a non-interactive install leaves the Commands rows as placeholders and warns, while `--primary python` fills them from Python. An unfilled required command is never silent.
2. **Idempotent re-runs.** Running `install` (or `sync`) twice at the same version changes nothing. Success criterion: a test asserts an identical tree hash (every directory path and every file's path and content hash, excluding `.git/`) before and after the second run, and a byte-identical lock.
3. **Customizations are never lost.** Customizations live in user-owned `.ai-factory/overrides/` and `config.md`, which no command ever writes. A local edit to any generated file (adapter, template, scaffolding) blocks `install`, `upgrade` and `sync` before anything is written, unless `--force`, which backs the file up first. The one deliberate exception is the inside of the managed `.gitignore`/`.gitattributes` blocks, which `install`/`upgrade` replace in place (see Managed git blocks). Success criteria: after an upgrade, `overrides/**` and `config.md` are byte-identical; an install, upgrade or sync over an edited adapter or an edited `.ai-factory/templates/` file exits 4 with an identical tree hash and a "move this into `overrides/`" message; with `--force` the backup is byte-identical to the pre-run file.
4. **Upstream drift is visible on every clone.** An override's review baseline is recorded only by `soloaifactory ack <path>`. An override that is unrecorded, stale (its upstream base changed since the ack) or orphaned (its base was dropped or renamed upstream) makes `status` exit 3 on any clone of the repository, including CI. Success criteria, each run on a committed-tree clone (`git clone` of a temp repo, so gitignored paths are absent): (i) ack on v1, upgrade to v2 → stale, named, with a review hint; after `ack`, exit 0. (ii) Override authored against v1 on a branch while main is upgraded to v2 and merged first, then the branch is rebased: whether or not the branch had acked, `status` on the rebased clone exits 3 (stale if acked on v1, untracked if not). (iii) A standalone override acked as "no base" on v1 whose name upstream adds in v2 → stale ("now shadows an upstream agent"). (iv) A replacement whose upstream base is renamed in v2 → orphaned until acked or moved. (v) A `.frontmatter.yml` that sets only `model` stays current across an upstream body edit and goes stale when upstream changes the `model` line. (vi) Two branches that ack different overrides and conflict in the lock: `install --relock` on the merge keeps both acks; a record the two sides disagree on becomes untracked; no other override changes state.
5. **Clean uninstall.** `uninstall` removes exactly what the CLI generated and still matches the lock, the managed git blocks (keeping the `projects/*` / `archive/*` ignore lines while either directory has content) and the lock, in a defined order. It never removes `config.md`, `overrides/`, `projects/*`, `archive/*`, edited generated files or any file the CLI did not generate.
6. **Dry-run and read-only commands write nothing and never prompt.** `install`, `upgrade`, `sync` and `uninstall` accept `--dry-run`, which prints the full plan (including detected config values) without prompting. `status`, `detect`, `show`, `version` and `sync --check` are always read-only. None of these creates a file or directory in the target, not even `.ai-factory/` on a fresh repo. Success criterion: tree-hash tests on a fresh and on an installed target.
7. **Small, portable runtime.** The CLI needs Node 24+ and uses only `node:` built-in modules (zero runtime `dependencies`, no lifecycle scripts). It needs no git binary, shell, `curl` or `tar`, makes no network calls except `status --remote`, and runs natively on Linux, macOS and Windows (CI matrix), including case-insensitive file systems, `core.autocrlf=true` and `core.symlinks=false` checkouts (see Cross-platform rules). *Using* the factory (agents, skills, templates) needs no Node at all.
8. **CI-friendly.** Works unattended with no TTY (detects `CI` or a missing TTY, or takes `--yes`), uses documented and frozen exit codes, lets callers supply any config value through flags, and documents a one-line `status` step that runs on Linux, macOS and Windows runners. OS and editor junk files and unmanaged files never change an exit code.
9. **The Verifier fails on unfilled required config.** `factory-verifier` reads the labels the config template uses (**Test**, **Lint**, **Type check**, **Build**), reports a placeholder, empty or `none` value on a Required row as `fail` ("not configured"), never `skipped`, and its Verdict Rules say so. `factory-build` stops for the human on a "not configured" failure instead of routing it to the Coder. A contract test keeps template, Verifier labels, the not-configured rule and the Step C routing aligned.
10. **Reproducible, pinned versions.** Every install records the package version and a digest of every packaged file that affects output (`framework/**`, `src/**`, `bin/**`; identical on every OS). `sync`, `status` and `ack` refuse to run with a different CLI version, or a different build of the same version, and print an actionable remedy (exit 4). `install` never changes the installed version; only `upgrade` does, to the running CLI's version; a downgrade needs `--allow-downgrade` and a same-version re-pin to a different build needs `--allow-unreleased`. Published versions are immutable on npm, and every one, including the first, carries a provenance attestation generated in CI from a tested commit.

## Non-Goals

- **User-level (global) installs** in v1: no `--scope`, no `$HOME/.cursor` / `$HOME/.claude` adapters, no global data dir, no `--dest` flag (the old `sync.sh --dest "$HOME"` option goes away with `sync.sh`). Nothing blocks adding it later: the lock keeps a `scope` record (always `project` in v1); readers preserve unknown record kinds; composition produces an in-memory path→bytes map that is written relative to an output root, which v1 anchors to the target repo root and a future user scope could anchor elsewhere with its own lock.
- **Supported installs from git branches, commit SHAs, tarballs or local checkouts.** Contributors may run `node <checkout>/bin/soloaifactory.js …`; the lock's framework digest then keeps that unreleased build from being mixed silently with a published one (Goal 10). `npx github:…` is not documented or supported.
- **Automatic re-exec of the pinned version.** `npx soloaifactory sync` (unpinned) at a version other than the lock's refuses and prints the exact `npx --yes --prefer-offline soloaifactory@<locked> sync` command; it does not spawn npx itself.
- **Runtime enforcement of provenance.** npx verifies registry integrity but does not require provenance; users with the optional devDependency can run `npm audit signatures`.
- **Offline first use.** `npx` needs the registry or its cache. The CLI itself makes no network calls except `status --remote`.
- **Detectors beyond Node, Python, Go and Rust** (.NET, Java/Maven/Gradle, Ruby/Bundler). Users of other stacks use `--set` or edit `config.md`. Each detector is additive.
- **Automatic text merging** of overrides with upstream changes. Drift is reported (Goal 4); the user updates the override and runs `ack`.
- **Frontmatter overrides beyond agents' `model` (optionally per tool as `cursor.model` / `claude.model`) and `description`**, and frontmatter overrides for skills. `readonly` and `shell` are safety properties and need a full replacement.
- **Disabling a shipped agent or skill.** A deleted generated file is restored on the next write run (with a warning). A future `overrides/<kind>/<name>.disabled` opt-out fits the layout without a lock format change.
- **Running the target's toolchain** to validate detected commands. Detection only reads files.
- **Monorepo or multi-package configs.** One `config.md` per repository, as today.
- **Background update checks or telemetry.**
- **Other distribution channels** (Homebrew, pipx/uvx, standalone binaries, a curl script). They could wrap the same package later.
- **A programmatic API.** The package is CLI-only (no `main`/`exports`).
- **`--json` output and printing changelog entries** during upgrade (upgrade prints the release-notes URL).
- **Migration from the bash/`cp -r` layout.** The project has no users; a repo with a copied `.ai-factory/` is handled by the generic adopt rules: adapters carrying the legacy marker `Generated by .ai-factory/sync.sh` count as generated (row 11, forceable), and the old `framework/` and `sync.sh` are reported (informational) as leftovers the user can delete.
- **Changing agent, skill or template content**, except: (a) generalizing `factory-archive`'s references to `.ai-factory/examples/`; (b) aligning `factory-verifier.md` with the config template labels, the not-configured rule and its Verdict Rules (Goal 9); (c) `factory-build`'s precondition 3 and a Step C "not configured → human" row; (d) the "Invoking subagents" paragraph in `factory-design`, `factory-plan` and `factory-build`, which names `.ai-factory/framework/` and `sync.sh`.

## Architecture Overview

### Key decisions

| Decision | Choice | Main reason |
|---|---|---|
| Runtime | **Node ≥ 24, plain ESM JavaScript, zero runtime dependencies** (only `node:` built-ins) | JSON, hashing, file system, argument parsing (`util.parseArgs`), prompts (`readline`) and a test runner (`node:test`) are built in; removes the bash portability, awk escaping, locale and bootstrap problems. See "Runtime choice" |
| Distribution | **npm**, published by GitHub Actions with **trusted publishing (OIDC) and provenance**, only after the full test matrix passes; invoked as **`npx soloaifactory@<version> <command>`** | Immutable versions, registry integrity checks, attestations tied to a commit and workflow, no long-lived token, no bootstrap script |
| Where the framework lives | **In the npm package** (`framework/` at the package root). Targets hold no copy of `framework/` or a generator script | Nothing upstream-owned sits in the target for users to edit; "pristine" is defined by the locked package version |
| What a target holds | User-owned `.ai-factory/overrides/` and `config.md`; generated adapters, `.ai-factory/templates/` and `.gitkeep` scaffolding; managed `.gitignore`/`.gitattributes` blocks; the committed lock | Only what the user owns or what Cursor, Claude Code and the agents must load from disk |
| Generator | **`soloaifactory sync [--check]`** replaces `sync.sh`; `sync.sh` is deleted | One implementation for generation, collision refusal, edit protection and removal |
| Customization | **Overrides layer**: full replacement, `.append.md`, and key-level `.frontmatter.yml` (agent `model`, per-tool `cursor.model`/`claude.model`, `description`) whose staleness is keyed on the overridden lines only | Upgrades never produce file-level conflicts; the most common customization (`model:`) neither drifts nor goes stale on unrelated upstream edits, and works in both tools |
| Edit protection | The lock stores the hash of every generated file; a generated file that matches neither the lock nor the new output is a **local edit** and blocks the run (`--force` backs up first) | Symmetric protection for adapters and templates (N7); the hashes are needed because the previous output depends on the previous overrides, which are not on disk any more |
| Drift baselines | **Only `ack <path>` records** an override's baseline; unrecorded, stale and orphaned overrides are attention items; a conflicted lock is repaired by **`install --relock`**, which keeps agreeing baselines | Correct under rebase and merge (N1) without forcing a mass re-ack after a lock conflict |
| Version pinning | The lock records the version and a **framework digest** (over `framework/**`, `src/**`, `bin/**`); `sync`/`status`/`ack` must run as that exact build; `install` never changes it; `upgrade` moves to the running CLI's version | Every clone and CI regenerates from the same release; no hidden upgrade |
| Filesystem policy | One **junk-file ignore list**; lowercase unit names with case-collision rejection; **no reads or writes through symlinks**; CRLF→LF on every text input; content-based text detection; exec bits preserved | Native Windows and macOS without permanent blocks, lost writes or writes outside the target (see Cross-platform rules) |
| Process model | **One process, compose in memory, then write**: validation, composition and planning finish before the first write; files are written with atomic renames and the lock last | No staging directory, no re-exec, no cross-version hand-off (N2, N4, N5 moot) |
| Install state | One committed **line-oriented TSV lock** `.ai-factory/factory.lock`, sorted by code-unit order, rewritten only when its content changes | Merges line by line (JSON objects conflict on trailing commas); one file keeps the "lock written last, atomically" guarantee; readable with one line in CI |
| Source repo | Canonical sources move to **repo-root `framework/`**; this repo's `.ai-factory/` becomes an ordinary install of itself (**self-host mode**: target root == package root), whose lock records constant `version`/`framework` sentinels | This repo's `.ai-factory/` has the same shape as any target, and CI dogfoods the CLI on it; framework PRs never conflict on the version or digest line. Replaces revision 2's `.factory-source` marker |
| Blank config | **`framework/config.template.md`**; `.ai-factory/config.md` becomes this repo's real config | Separates the shipped template from this repo's state |
| Examples | Repo-root **`examples/`**, not in the npm package | Package contents are an allowlist (`files`) |

### Runtime choice

The human decision is Node on npm. The trade-off, stated honestly:

| | Bash script (revision 2) | **Node on npm (chosen)** | Python via uvx / pipx | Go static binary |
|---|---|---|---|---|
| Prerequisite to install / upgrade / sync / status | bash 3.2, curl or wget, tar (macOS and Linux only) | **Node 24+ with npm** | Python 3.11+ and uv (or pipx) | None at run time; a download per OS/arch |
| Prerequisite to *use* the factory | None | **None** (plain Markdown) | None | None |
| Windows | Not supported | **Supported** (npm cmd shims) | Supported | Supported (per-target builds) |
| Integrity and authenticity | SHA-256 from the same release (integrity only); relied on immutable releases and tag protection | **Registry sha512 integrity, immutable versions, Sigstore provenance via trusted publishing** | PyPI trusted publishing and attestations | Self-managed checksums/signing (cosign), notarization on macOS |
| Pinning every clone to one release | Tag URL; the old installed script bootstraps the new one (frozen cross-version contract) | **`npx soloaifactory@<lock version>`**; each version runs only its own code | `uvx soloaifactory==<v>` | Version manager or per-version download |
| Implementation pitfalls | awk escaping, BSD vs GNU tools, locale collation, piped-script truncation, re-exec hand-off | Windows renames (`EPERM`), CRLF, case folding, symlinks; all handled below | No built-in YAML; `tomllib` built in (a real advantage for `pyproject.toml`/`Cargo.toml` detection) | Build/release matrix; contributors need Go |
| Test tooling | Custom bash harness | **`node:test` built in** | `unittest` built in | `go test` |
| Fit with the audience | Universal on Unix | Most Cursor / Claude Code users already have Node; Python/Go/Rust repos may not | Strong for Python repos, uncommon elsewhere | Best for users, heaviest for maintainers |

**Cost accepted:** whoever runs the CLI (and the target's CI, if it runs `status`) needs Node 24+. Repos in other ecosystems do not get a Node dependency in their project; the factory's day-to-day use stays plain Markdown.

**Minimum Node version: 24** (`engines.node: ">=24"`). As of this design, Node 26 is the Active LTS line and Node 24 is the oldest LTS line supported beyond the expected v1 lifetime (maintenance until April 2028). Node 22 reaches end of life in April 2027, five months away, which would force an `engines` bump (a breaking change) almost immediately. Every API the CLI uses (`util.parseArgs`, `node:test`, `fetch`, `fs.cpSync`, `crypto.hash`) is stable on 24. CI tests 24 and 26. `bin/soloaifactory.js` checks `process.versions.node` with syntax that old Node can parse and prints "soloaifactory needs Node 24 or newer (found X)" with exit 1 instead of a syntax error.

**JavaScript, not TypeScript-compiled-to-JS.** The published files are the repository's source files: no build step, no source maps, and what provenance attests is exactly what a reviewer reads on GitHub. Type safety comes from JSDoc annotations checked by `tsc --noEmit --checkJs` (`typescript` is the only devDependency, never shipped). Either choice ships zero runtime dependencies; this one removes a build artifact from the release path.

### What lives where

| Location | Contents | Owner | Written by the CLI? |
|---|---|---|---|
| npm package `soloaifactory@X.Y.Z` | `bin/`, `src/`, `framework/agents/**`, `framework/skills/**`, `framework/templates/**`, `framework/config.template.md`, `README.md`, `CHANGELOG.md`, `LICENSE` | Upstream, immutable per version | n/a |
| `.ai-factory/overrides/**` | Replacements, appends, frontmatter overrides | User | **Never** |
| `.ai-factory/config.md` | Project config | User | Created once if absent; never overwritten or deleted |
| `.ai-factory/projects/*`, `.ai-factory/archive/*` (except `.gitkeep`) | Working and archived feature artifacts | User | Never |
| `.cursor/agents/<name>.md`, `.cursor/skills/<name>/**`, same under `.claude/` | Adapters for each composed agent and skill, with marker | CLI (generated) | Yes, hash-tracked |
| `.ai-factory/templates/*` | Composed templates (no marker) | CLI (generated) | Yes, hash-tracked |
| `.ai-factory/projects/.gitkeep`, `.ai-factory/archive/.gitkeep` | Scaffolding | CLI (generated) | Yes, hash-tracked |
| `.gitignore`, `.gitattributes` | One delimited block each | CLI (block only) | Block only |
| `.ai-factory/factory.lock` | Install state | CLI | Yes |
| `.ai-factory/.factory-backup/`, `.ai-factory/.factory-run/` | `--force` backups; mutex | CLI | Yes (gitignored) |

**Never written or deleted, in any mode:** anything outside the target directory (and nothing reached through a symlink, see Cross-platform rules); any adapter-directory file the lock does not track and that is not part of the current composition; any file under `.ai-factory/` that is not generated, the lock, or a working directory.

**Generated directories** are exactly `.ai-factory/templates/` and each `.<tool>/skills/<name>/` that the current composition generates. `.<tool>/agents/`, `.<tool>/skills/` and `.ai-factory/` themselves are never generated directories, so a repo's own non-factory agents and skills are invisible to the CLI. An **unmanaged file** is a file inside a generated directory that is neither in the lock nor in the composed output and is not on the junk-file ignore list (for example a hand-made `.ai-factory/templates/notes.md`); leftover `.ai-factory/framework/` and `.ai-factory/sync.sh` from a manual copy are reported the same way. Unmanaged files and leftovers are left alone and reported by `status` as **informational** lines (a "move this into `overrides/`" or "delete" hint) that **never change the exit code**. A generated directory that still holds unmanaged or junk files is not removed. Revision 2's "`sync.sh` owns `.ai-factory/templates/` and deletes anything else" rule is gone.

**Junk-file ignore list** (one list in `src/fs-policy.js`, matched against a file's base name, case-insensitively): `.DS_Store`, `Thumbs.db`, `desktop.ini`, `*~`, `*.swp`, `*.swo`, `.#*`, `*.orig`, `*.rej`. Matching files are skipped everywhere the CLI scans: `overrides/` (never an invalid layout, never copied into a replacement skill), the framework tree (packaged and self-host, so neither the output nor the digest sees them), and generated directories (never unmanaged, never hashed). A contract test asserts no committed `framework/` file matches the list, and the packaging test asserts the self-host framework scan equals the `framework/` entries of `npm pack --dry-run --json`, so self-host output and the published build cannot diverge.

### Overrides composition

User-owned layout, all optional:

```
.ai-factory/overrides/
  agents/<name>.md                 # full replacement of framework/agents/<name>.md, or a new agent
  agents/<name>.append.md          # appended to the end of the framework agent body
  agents/<name>.frontmatter.yml    # key-level frontmatter changes (model, cursor.model, claude.model, description) to the framework agent
  skills/<name>/SKILL.md (+ files) # full replacement of framework/skills/<name>/, or a new skill
  skills/<name>/SKILL.append.md    # appended to the framework skill's SKILL.md (directory holds nothing else)
  templates/<name>                 # full replacement of framework/templates/<name>, or a new template
```

Rules:

- **Agents:** the set is the union of `framework/agents/*.md` and replacement files in `overrides/agents/`. The base is the replacement if present, otherwise the framework file. `<name>.frontmatter.yml` replaces or adds the listed keys in the base frontmatter; `<name>.append.md` is appended after the body, separated by one blank line. Appends and frontmatter overrides apply **only to framework agents**: combining either with a replacement of the same name is an invalid layout (put the change in the replacement). Rendering then maps the canonical frontmatter per tool, as `sync.sh` does today (Cursor keeps `readonly` and drops `shell`; Claude drops both and turns `readonly: true` into `tools: Read, Grep, Glob`, plus `, Bash` when `shell: true`), and resolves per-tool model keys: for tool T the emitted `model` is `T.model` if present, else `model`, else none; dotted keys are never emitted.
- **Frontmatter override application** is line-based so every other byte of the base stays identical: for each key in the override, the base's line for that key (and, for a block scalar, its indented continuation lines: its **line span**) is replaced by the override's lines for that key, verbatim; a key absent from the base is inserted before the closing `---`. Allowed keys: `model`, `cursor.model`, `claude.model`, `description`. Per-tool keys sit next to `model` in the composed canonical frontmatter and are resolved by the renderer as above, so `model: inherit` plus `claude.model: sonnet` gives Claude `sonnet` and Cursor `inherit`. A per-tool key for a tool outside `targets` is valid and simply unused. Grammar in Data Model §5.
- **Frontmatter contract for every agent and skill** (framework, replacement and new), parsed by the same subset reader as `.frontmatter.yml` (Data Model §5), so a construct outside the subset is exit 6 with file and line:
  - Agents: `name` (required, must equal the file stem) and `description` (required); known optional keys `model`, `cursor.model`, `claude.model`, `readonly` and `shell` (`true`/`false`), and `tools`; any other key is passed through verbatim to both tools. `tools` together with `readonly: true` is exit 6 ("the Claude renderer derives `tools:` from `readonly`; drop one"), because the output would carry a duplicate key.
  - Skills (`SKILL.md`): `name` (required, must equal the directory name) and `description` (required); other keys pass through verbatim.
  - A contract test parses every framework agent and `SKILL.md` frontmatter under this contract.
- **Skills:** a directory containing `SKILL.md` replaces the framework skill directory wholesale. A directory containing only `SKILL.append.md` appends to the framework `SKILL.md` and copies the other framework files unchanged. `SKILL.append.md` next to any other file is an invalid layout.
- **Templates:** the set is the union of `framework/templates/*` and `overrides/templates/*`; the override wins. Templates are copied byte for byte (text files after LF normalization) with **no marker**, so nothing leaks into documents derived from them. They are always written under the **target repo root** (`<target>/.ai-factory/templates/`); there is no other destination.
- **Invalid layout** (exit 6, detected before any write by every command that composes; junk-list files are ignored first): an unknown file type or top-level entry under `overrides/`; append or frontmatter next to a same-name replacement; `SKILL.append.md` with siblings; a frontmatter file outside the grammar or with a key other than the four allowed; a frontmatter-contract violation (above); a **unit name** (agent stem, skill directory, template file name) outside `[a-z0-9][a-z0-9._-]*`; a path inside a skill directory outside the ASCII set (letters, digits, `.`, `_`, `-`, `/`); two composed output paths that are equal ignoring case. The message names the file and, for YAML, the line. The same name rules are asserted for `framework/` by the contract test.
- **Orphans:** an append or frontmatter override whose framework base no longer exists cannot be applied; it is skipped and reported as an attention item until the user deletes or retargets it (it cannot be acked). A replacement whose base no longer exists still generates as a standalone agent, skill or template, and is reported as **orphaned** until acked (see below), so a customization of an agent upstream renamed is never silently unused.

Marker (agents after the frontmatter; skill `.md` files after the frontmatter, or at the top when there is none):

```
<!-- Generated by soloaifactory from framework/agents/factory-coder.md + .ai-factory/overrides/agents/factory-coder.append.md - do not edit; customize in .ai-factory/overrides/ and run "soloaifactory sync". -->
```

The marker carries no version, so an upgrade that leaves an agent unchanged leaves its adapter byte-identical. The literal `Generated by soloaifactory`, or the legacy `Generated by .ai-factory/sync.sh`, identifies generated files when no lock records them (adoption and collision checks), so a repo carrying `sync.sh`-era adapters gets row 11 (blocked, forceable), not row 12.

### Generated-file decision table (install, upgrade, sync)

For every path in the union of the lock's `gen` records and the newly composed output (a lock path and an output path that differ only in case are one entry, see Cross-platform rules): `lock` is the recorded hash, `disk` the hash on disk now, `exp` the hash of the new output. Text files (content-based detection, see Cross-platform rules) are hashed after CRLF→LF normalization, so a `core.autocrlf=true` checkout never looks edited; binary files are hashed and written byte for byte. Hashes never include the file mode. "Blocked" means the run lists the file and exits 4 before writing anything; with `--force` the file is first copied to `.ai-factory/.factory-backup/<UTC timestamp>/<path>` and the action proceeds.

| # | In lock | In new output | On disk | Action | Lock records |
|---|---|---|---|---|---|
| 1 | yes | yes, `exp == lock` | `== lock` | skip | `lock` |
| 2 | yes | yes, `exp != lock` | `== lock` | **update** | `exp` |
| 3 | yes | yes | `== exp`, `!= lock` | skip (already current: interrupted run, or a teammate's regenerated files arrived by merge) | `exp` |
| 4 | yes | yes | `!= lock`, `!= exp` | **blocked** (local edit); `--force`: back up, write | `exp` |
| 5 | yes | yes | missing | **restore** + warning | `exp` |
| 6 | yes | no | `== lock` | **remove** (dropped upstream, override removed, or target dropped) | – |
| 7 | yes | no | `!= lock` | **blocked**; `--force`: back up, remove | – |
| 8 | yes | no | missing | drop record | – |
| 9 | no | yes | missing | **add** | `exp` |
| 10 | no | yes | `== exp` | **adopt** | `exp` |
| 11 | no | yes | `!= exp`, generated (current or legacy marker present, or a template or `.gitkeep` path) | **blocked**; `--force`: back up, write | `exp` |
| 12 | no | yes | `!= exp`, adapter without either marker | **collision**: refuse, exit 4. `--force` never applies | – |

For files inside a skill directory, "marker present" is decided by that skill's `SKILL.md`. On POSIX, a generated file whose exec bit differs from the expected mode (below) is reported "out of date" and fixed by the next write run with a `chmod` plan line; it is never "edited". The block message is: "`<path>` was edited locally. Generated files are rewritten from the soloAIfactory package and `.ai-factory/overrides/`; move your change into `.ai-factory/overrides/` (see README), then re-run, or re-run with `--force` (backs it up to `.ai-factory/.factory-backup/`)". The collision message tells the user to rename or remove their own file, or rename the soloAIfactory one with an override. Revision 2's "local edit to `framework/` blocks" rule and its 11-row payload table no longer exist: there is no `framework/` in a target.

### Cross-platform rules

All live in `src/fs-policy.js` and `src/hash.js` and apply to every command, read-only ones included.

- **Text vs binary.** A file is text iff its bytes are valid UTF-8 and contain no NUL byte; everything else is binary. Text files are LF-normalized when read, hashed and written; binary files are never normalized. The same rule applies to the framework, overrides and disk content, so skill scripts (`.sh`, `.py`, `.js`, `.ts`, `.toml`, …) are covered without an extension list. The `.gitattributes` block uses git's own content detection (`text=auto eol=lf`) for the same trees (Data Model §3).
- **Every input is CRLF-normalized** on read: the lock, overrides (replacements, appends, frontmatter), `config.md`, `framework/config.template.md`, frontmatter, `package.json` and TOML files. A CRLF lock therefore parses; a CRLF append cannot produce mixed line endings or per-machine `gen` hashes.
- **Exec bits.** A generated file is written with mode `0o755` when its source (packaged framework file, or override file) has any exec bit, else with the default mode. The packaging test asserts every framework file committed as `100755` keeps an exec bit in the `npm pack` tarball. On Windows (`process.platform === 'win32'`) modes are not tracked: they are neither written, compared nor reported, and hashing never depended on them.
- **Case.** Unit names are lowercase-only (exit 6) and the composed path set must be free of case-insensitive duplicates (exit 6). A lock path and an output path that differ only in case (a case-only rename of a file inside a skill directory) are paired as one decision-table entry; its write unlinks the old name and renames the temp file onto the new one, so a case-insensitive file system never loses the file to a row-6 removal.
- **Symlinks.** Before planning, the CLI `lstat`s every managed path and each of its parent directories below the target root (`.ai-factory/`, `.cursor/`, `.claude/`, their `agents/` and `skills/` directories, each generated skill directory, the lock, `.factory-run/`, `.factory-backup/`), and every entry under `overrides/`. Any symlink is refused with exit 4 naming it ("soloaifactory does not read or write through symlinks; replace `<path>` with a real file or directory"). With `core.symlinks=false`, a committed symlink checks out as a small regular file where a directory is expected; that is also refused with exit 4 and a hint naming `core.symlinks`. So the CLI never writes outside the target and the two tools' adapter directories can never alias each other.
- **Self-host detection** compares `fs.realpathSync.native` of the target root and the package root, case-folded on win32, so drive-letter or path case differences cannot hide self-host mode.
- **POSIX paths everywhere.** Lock paths, plan output and every digest input use `/`-separated relative paths built by the CLI, never `path.relative` output; the cross-OS digest assertion (Testing) checks it.

### Override baselines and drift

The **base** of an override is its framework counterpart in the locked package: `framework/agents/<name>.md` for `agents/<name>.md` and `<name>.append.md`; `framework/skills/<name>/SKILL.md` for `SKILL.append.md`; the whole `framework/skills/<name>/` directory for a replacement skill; `framework/templates/<name>` for a template. An append's base is the **whole** base file, a deliberately conservative choice: an append's meaning depends on the body it follows, so any upstream change to that body is worth a review. A `<name>.frontmatter.yml`'s base is only the **line spans of the keys it overrides** in `framework/agents/<name>.md` (`cursor.model` and `claude.model` map to the `model` span). The **digest** of a file base is the SHA-256 of its LF-normalized bytes; of a directory base, the SHA-256 of its sorted `<POSIX relpath>\t<sha256>\n` lines (junk files excluded); of a frontmatter base, the SHA-256 of its sorted `<key>\t<sha256 of the key's line span, or - when the base lacks the key>\n` lines, one per distinct base key. So a `model`-only override stays current across body and description edits and goes stale when upstream changes or adds its `model` line, or when the user changes which keys the override sets.

**Only `soloaifactory ack <path>…` writes `override` records.** `install`, `upgrade` and `sync` never create, change or infer them; they only drop the record of an override file that no longer exists. `ack` records baseline = the current base digest (or `-` when there is no base) and the CLI version as `acked`.

| State (computed by every command; reported by `status`) | Condition | Attention? |
|---|---|---|
| current | recorded; base exists and baseline == digest; or no base and baseline `-` | no |
| **untracked** | override exists, no record | yes, until `ack` |
| **stale** | recorded; base exists; baseline != digest (`-` never matches, so a standalone override whose name upstream adds becomes stale) | yes, until `ack` |
| **orphaned** (replacement) | recorded with a digest; base no longer exists (dropped or renamed upstream) | yes, until `ack` records `-` (keep as standalone) or the user moves it |
| **orphaned** (append / frontmatter) | base no longer exists | yes, until deleted or retargeted; not ackable |

Because baselines live only in the committed lock and are written only by an explicit human action, rebases and merges cannot launder drift: an override authored against v1 is either acked against v1 (and goes stale when v2 lands) or untracked (and flagged) on every clone. `install --relock` (Lock failure and recovery) keeps only baselines that a side of the conflict recorded and the other did not contradict, so drift is never silently cleared either.

For each stale override `status` prints the base path, the acked and current versions, and ready-to-run review commands that work in any shell (no process substitution), since the base text is no longer in the repository:

```
stale  .ai-factory/overrides/agents/factory-coder.md
       base framework/agents/factory-coder.md changed since your ack on 0.1.0 (installed: 0.2.0)
       review: npx --yes --prefer-offline soloaifactory@0.1.0 show agents/factory-coder.md > base-0.1.0.md
               npx --yes --prefer-offline soloaifactory@0.2.0 show agents/factory-coder.md > base-0.2.0.md
               git diff --no-index base-0.1.0.md base-0.2.0.md
       then:   npx --yes --prefer-offline soloaifactory@0.2.0 ack .ai-factory/overrides/agents/factory-coder.md
```

### Versions and pinning

The **running CLI's own package version is the only version it can install**. There is no `--version` payload flag.

| Command | No lock | Lock at same version and framework digest | Same version, different digest (unreleased/local build) | Lock at an older version | Lock at a newer version |
|---|---|---|---|---|---|
| `install` | Fresh install (or adopt) | Reconcile | Refuse, exit 4, digest message | Refuse, exit 4: "installed 0.1.0, this is 0.2.0: run `npx --yes --prefer-offline soloaifactory@0.2.0 upgrade`, or `npx --yes --prefer-offline soloaifactory@0.1.0 install` to keep 0.1.0" | Refuse, exit 4 (same message, worded as a downgrade) |
| `upgrade` | Refuse, exit 5 | Reconcile | Refuse, exit 4, digest message; with `--allow-unreleased`: warn, then regenerate from this build and re-pin the digest | **Upgrade** | Refuse, exit 4: "this CLI (0.1.0) is older than the installed version (0.2.0); that is a downgrade. Run `npx --yes --prefer-offline soloaifactory@0.2.0 …`, or re-run with `--allow-downgrade`" |
| `sync`, `ack`, `status` | Exit 5 | Run | Refuse, exit 4, digest message | Refuse, exit 4 with the exact `npx --yes --prefer-offline soloaifactory@<locked> <command>` line | Same |
| `uninstall` | Exit 5 | Run | Run | Run (only the lock is needed) | Run, unless the lock `format` is newer than this CLI understands (exit 4) |

**Digest message** (same version, different digest). It never just repeats the user's command; it depends on whether the running CLI is a local checkout (its package root contains `.git`):

- Local checkout: "soloaifactory: the lock was written by a different build of 0.2.0 than this local checkout (digest `<lock 12 hex>` vs `<this 12 hex>`). Run the published CLI instead, outside this checkout: `npx --yes --prefer-offline soloaifactory@0.2.0 <command>`. To deliberately pin the repo to this local build: `node <checkout>/bin/soloaifactory.js upgrade --allow-unreleased`."
- Packaged CLI: "soloaifactory: the lock was written by a different build of 0.2.0 (digest `<lock>` vs `<this>`), probably a local or unreleased build. To regenerate from this build and re-pin the lock, run `npx --yes --prefer-offline soloaifactory@0.2.0 upgrade --allow-unreleased` and commit the result."

`--allow-unreleased` exists so a contributor's local run cannot re-pin a shared repo by accident; the warning names both digests.

**Self-host mode.** When the resolved target root is the CLI's own package root (Cross-platform rules: `realpathSync.native`, case-folded on win32), the target is the soloAIfactory source repo dogfooding itself: the framework is the working tree, the version and digest gates are skipped, and `upgrade` is refused (exit 4, "run `npm run sync` in the source repo"). Its lock records the constant sentinels `version 0.0.0-self` and `framework self`, so framework PRs touch only `gen` lines and never conflict on one shared line. A non-self-host CLI that reads `framework self`, or that runs where the target's `package.json` has `"name": "soloaifactory"`, refuses with exit 4: "this is the soloAIfactory source repo; use `npm run check` / `npm run sync`". An installed devDependency lives under `node_modules/`, so it can never match a target root.

**How every clone and CI uses the same release:**

- The canonical form is `npx --yes --prefer-offline soloaifactory@<version> <command>`, with the version read from the lock. The CLI prints this form whenever it refuses or advises: `--yes` skips npx's install prompt in non-interactive contexts and `--prefer-offline` uses cached registry metadata instead of revalidating it. The CI step is in Invocation forms.
- **Optional for Node repos:** `npm install --save-dev --save-exact soloaifactory@<version>`, after which `npx soloaifactory <command>` resolves to `node_modules` (no network, works offline) and `npm audit signatures` verifies provenance. Upgrading becomes `npm install -D -E soloaifactory@<new> && npx soloaifactory upgrade`. `upgrade` prints that hint when `package.json` declares the dependency. `status` compares the **declared spec** in `package.json` (`devDependencies` or `dependencies`), never `node_modules` (absent on a fresh CI clone): an exact version other than the lock's, or a range (`^`, `~`, `*`, …), is an attention item with a "pin `--save-exact` to `<locked>`" hint. The CLI never edits `package.json`.
- **Offline and the npx cache:** without `--prefer-offline`, npx revalidates the package metadata with the registry on every run; the tarball comes from the npm cache when present and is verified against its sha512 integrity. The cache can be cleaned or garbage-collected, so a cached version is not guaranteed. `npx --offline soloaifactory@<v> status` works if that version is cached and fails with npm's `ENOTCACHED` otherwise. The first run on a machine always needs the registry (Non-Goal).

### Process model

```
soloaifactory <command> [flags]                     (one process; no staging dir, no exec, no child processes)
│
├─ parse args with util.parseArgs({strict: true})          → exit 2 on any usage error, before touching the target
│                                                             (no command: usage on stderr, exit 2; only an explicit `install` installs)
├─ resolve TARGET: --dir | nearest ancestor of cwd containing .git (dir or file) | cwd
│  self = realpathSync.native(TARGET) == realpathSync.native(PACKAGE_ROOT)  (case-folded on win32)
├─ load PACKAGE: framework/ (junk list skipped; text LF-normalized, binary verbatim), digest over framework/, src/, bin/
├─ symlink check on managed paths and overrides/ (every command that reads them; not detect/show/version)  → exit 4
│
├─ status | detect | show | version | sync --check | any --dry-run ── read-only path (no mutex, no writes, no prompts)
│
├─ write commands (install, upgrade, sync, ack, uninstall):
│    acquire mutex TARGET/.ai-factory/.factory-run/  (creates .ai-factory/ if absent; removed again if the run aborts before writing) → exit 7 if held
├─ read lock (CRLF-normalized)                              → exit 5 (none, where required) / exit 4 (unparseable → points to --relock; format too new)
│                                                             install --relock: lenient parse of a conflicted lock (Lock failure and recovery)
├─ version gate (table above; `framework self` outside self-host → exit 4 "source repo")  → exit 4
├─ scan (junk list skipped) + validate overrides and frontmatter contract  → exit 6 (invalid layout)
├─ COMPOSE expected output in memory: Map<repo-relative POSIX path, {bytes, mode}> for the selected targets
│                                                             → exit 6 on case-insensitive duplicate paths
├─ PLAN (pure): generated-file decision table, exec bits, override states, git block diffs, config step (install)
├─ refuse: collisions → exit 4; blocked edits without --force → exit 4   (nothing has been written)
├─ config (install, config.md absent, no --no-config): detect + --set (+ --primary)
│    interactive and not --dry-run → one summary prompt [A]ccept / [e]dit / [s]kip
│    --dry-run or non-interactive → no prompt; detected values shown in the plan
├─ print plan;  --dry-run → exit 0
├─ interactive install / upgrade / uninstall: "Apply N changes? [Y/n]"   (declined → release mutex, exit 0)
├─ APPLY, in order:
│    1. --force backups → .ai-factory/.factory-backup/<UTC ts>/<path>
│    2. writes: temp file in the same directory (mode 0o755 when expected) + rename (retry on Windows EPERM/EBUSY with backoff); chmod-only fixes
│    3. removals, then empty generated directories
│    4. config.md (only if absent)
│    5. .gitignore / .gitattributes blocks (only if content differs; install/upgrade only)
│    6. factory.lock (temp + rename), only if its content differs — ALWAYS LAST
│    any failure in 1–6 → stop, delete own temp files, release mutex, exit 1:
│      "soloaifactory: failed after N of M changes (<error>). The lock was not updated; re-run the same command to finish."
└─ summary; exit 3 if the post-run status has any attention item, else 0
```

Properties:

- **Refused runs write nothing.** Every refusal (exit 2, 4, 5, 6, 7) happens before APPLY. Override validation and composition, the only steps that can fail on user input, finish in memory first, so revision 2's "`sync.sh` fails after payload writes" state (N3) cannot arise from a bad overrides layout.
- **Interrupted or failed runs reconcile.** Each write is an atomic rename and the lock is written last. A re-run finds already-written files equal to `exp` (rows 3 and 10) and continues; backed-up files now match `exp`. Temp files use the name `.<file>.soloaifactory-tmp-<pid>`; leftovers from a killed process are deleted by the next write run in the directories it manages.
- **Mutex.** `fs.mkdirSync` without `recursive` is atomic. The owner file holds `<pid> <hostname>`. If the directory exists, the run reclaims it with a warning when the host matches and `process.kill(pid, 0)` throws `ESRCH`; otherwise it exits **7** (transient: "another soloaifactory run holds `<path>` (pid, host); retry, or delete the directory if that host is gone"), distinct from the permanent refusals of exit 4, so scripts can retry 7 safely. `SIGINT`/`SIGTERM` handlers release it. **`ack` takes the mutex** (it writes the lock), like every write command; read-only commands never do.
- **No network.** The only network call is `status --remote`: a `fetch` of `<registry>/soloaifactory/latest`, where the registry is `npm_config_registry` when set (npm sets it for processes it spawns, including under npx) and `https://registry.npmjs.org/` otherwise. `.npmrc` files are not read, and Node's `fetch` uses `HTTPS_PROXY`/`HTTP_PROXY`/`NO_PROXY` only when `NODE_USE_ENV_PROXY=1`; both limits are documented in the README and named in the exit-1 error message when the fetch fails.
- **Deterministic ordering.** All sorting (lock records, composition, digests, plan output) uses one comparator, `(a, b) => (a < b ? -1 : a > b ? 1 : 0)` on JavaScript strings, which compares UTF-16 code units and ignores the locale. Managed paths are validated to ASCII, where this equals byte order. `localeCompare` and `Intl.Collator` are banned in `src/` by the lint script.

### Lock failure and recovery

- **Unparseable** means: a missing `format`, `version` or `framework` record; a known record kind with the wrong field count; a non-hex hash (except `framework self`); a duplicate path among `gen` or among `override` records; a path outside the allowed character set; or any line starting with `<<<<<<<`, `|||||||`, `=======` or `>>>>>>>`. A `format` greater than 1 is refused as "written by a newer soloaifactory". The lock is CRLF-normalized before parsing, so a CRLF checkout is not unparseable.
- **Unknown record kinds** are kept verbatim and written back on every rewrite, after the known kinds and sorted by full line (one rule; the tests check exactly this), so an older CLI reconciling a lock written by a newer minor version never drops records. Across an `upgrade --allow-downgrade` they are preserved too, so a record the older CLI could not maintain may be trusted again by the newer one later; this is accepted and documented, since the newer CLI re-validates its own record kinds on read.
- **Lock conflicts are expected.** Records are sorted, so branches that change neighbouring records (two different agents' adapters, two upgrades) conflict in git even though they touch different lines. On an unparseable lock every command exits 4 with: "`.ai-factory/factory.lock` is unparseable (<reason>). Repair it with `npx --yes --prefer-offline soloaifactory@<version> install --relock --target <targets>`" (version and targets quoted from the lock when readable; otherwise the message points at `git log -p .ai-factory/factory.lock` and says to pass `--target` explicitly so a cursor-only repo does not gain `.claude/`).
- **`install --relock`** parses the lock leniently and rebuilds it without discarding agreeing baselines:
  1. Conflict hunks are split into two sides (`<<<<<<<` … `=======` is one side, `=======` … `>>>>>>>` the other; a diff3 `|||||||` base section is discarded). Outside hunks, two records of the same kind and path (a hand merge that kept both sides) also count as two sides. Everything else is common.
  2. `format` must be readable and at most 1. `scope` must be `project`. `version`/`framework`: the running CLI's version and digest must match one side (or the common record); otherwise exit 4 naming the side versions and the command for the newer one. `targets`: the union of the sides, unless `--target` is given.
  3. `override` records, per path: kept when both sides agree or only one side has the record; **dropped (the override becomes untracked) when the sides disagree**. Records for override files that no longer exist are dropped as usual. Baselines are never inferred from disk.
  4. `gen` records are all rebuilt by the normal decision table run as an install: a composed path whose disk content equals `exp` is adopted (row 10), a missing one is added (row 9), a differing one is blocked (row 11, forceable) or a collision (row 12). A path recorded by either side but no longer composed is removed when its disk hash equals either side's recorded hash (row 6), and blocked otherwise (row 7).
  5. Unknown kinds: the union of distinct lines. The plan lists every kept, dropped and untracked baseline; `--dry-run` works as usual. On a parseable lock `--relock` behaves exactly like `install`.
- Deleting the lock and running `install` still works as a last resort (exit 3 afterwards: every override untracked), but no message recommends it.
- **One lock file, not two.** Splitting `override` records into a separate `overrides.lock` would keep ack changes and `gen` churn from ever touching the same hunk, but two files cannot be replaced in one atomic rename, which would reintroduce a half-written state the "lock written last" rule exists to prevent. With kind-ordered records the only shared boundary is one line pair, and `--relock` makes the remaining conflicts cheap, so the split is not worth it.

### Config onboarding

**Detection** is read-only, implemented as one module per ecosystem returning `key=value` pairs. It never executes anything from the target. It runs during `install` only when `.ai-factory/config.md` does not exist, and on demand through `soloaifactory detect`, which prints a full rendered config proposal to stdout and writes nothing.

| Marker file(s) | Language / runtime | Package manager | Test | Lint | Type check | Build | Format |
|---|---|---|---|---|---|---|---|
| `package.json` (+ lockfile) | TypeScript if `tsconfig.json`, else JavaScript; Node version from `.nvmrc` / `engines.node` | `pnpm-lock.yaml`→pnpm, `yarn.lock`→yarn, `bun.lock[b]`→bun, else npm | `<pm> test` if `scripts.test` is a real script (see below) | `<pm> run lint` if `scripts.lint` | `<pm> run typecheck` if script, else `npx tsc --noEmit` if `tsconfig.json` | `<pm> run build` if script | `<pm> run format:check` if script, else `npx prettier --check .` if Prettier config |
| `pyproject.toml` / `requirements*.txt` | Python; version from `requires-python` / `.python-version` | `uv.lock`→uv, `poetry.lock`→poetry, else pip | `pytest` (prefixed `uv run` / `poetry run`) if pytest is configured or referenced, or `tests/` holds Python files | `ruff check .` if ruff configured, else `flake8` if configured | `mypy .` if mypy configured | none | `ruff format --check .` / `black --check .` |
| `go.mod` | Go; version from the `go` directive | go modules | `go test ./...` | `golangci-lint run` if `.golangci.y*ml`, else `go vet ./...` | none (compiler) | `go build ./...` | `test -z "$(gofmt -l .)"` |
| `Cargo.toml` | Rust; `edition` / `rust-toolchain*` | cargo | `cargo test` | `cargo clippy -- -D warnings` | none | `cargo build` | `cargo fmt --check` |

- `package.json` is read with `JSON.parse` (a parse error leaves the Node values as placeholders and warns). TOML files are read with a small line scanner that recognizes table headers (`[tool.ruff]`, `[tool.pytest.ini_options]`, `[tool.mypy]`, `[tool.poetry]`, `[package]`) and simple `key = "value"` lines; it does not parse full TOML and fails soft to placeholders.
- **Placeholder test scripts are absent (N12).** A `scripts.test` that contains `no test specified` (case-insensitive), or that consists only of `echo …` followed by `exit 1`, is treated as missing.
- **Test signal.** Node has one when it has a real `scripts.test`; Python when pytest is configured or referenced (`[tool.pytest.ini_options]`, `pytest.ini`, `conftest.py`, a `pytest` dependency) or `tests/` holds Python files; Go when `go.mod` exists; Rust when `Cargo.toml` exists.
- **Primary ecosystem.** `--primary node|python|go|rust` wins. Otherwise, if exactly one detected ecosystem has a test signal, it is primary. If none has one, the first detected ecosystem in table order is primary (Test stays a placeholder). If several have one: interactive mode asks; **non-interactive mode leaves every Commands row as a placeholder, warns naming the candidates and `--primary`, and fills only the Tech Stack bullets** (listing all detected ecosystems under Architecture Notes). A repo with a `package.json` used only for Prettier or husky has no Node test signal, so its Python, Go or Rust runner wins.
- **Precedence** within the primary ecosystem, highest first: `--set KEY=VALUE`, package scripts, a `Makefile` target named `test`/`lint`/`build` (→ `make test` etc.), ecosystem defaults.

**Rendering** is keyed on **labels** in `framework/config.template.md`, so the template stays usable by hand:

- Bullet `- **<Label>**: <placeholder>` → keep the text up to and including `": "`, then the value.
- Table row `| **<Label>** | <placeholder> | <notes> |` → replace cell 2; a `|` in the value is written as `\|`.
- Values are inserted with `indexOf`/`slice`; no regex replacement strings are built from user values. A value containing a newline is a usage error (exit 2). No value for an optional command → `none`. No value for **Test** or **Lint** → placeholder kept and a warning naming each unfilled required label.

**Interactive vs non-interactive:** interactive when `process.stdin.isTTY && process.stdout.isTTY` and none of `--yes`, `--non-interactive` or `CI` is set (under npx, stdin is the terminal, so no `/dev/tty` trick is needed). The detected values are shown as one summary with `[A]ccept / [e]dit / [s]kip config`; edit walks the values (Enter keeps, `-` sets `none`, anything else replaces). `--dry-run` never prompts.

**Exit codes follow one rule for every command:** a run that completes exits 3 if the post-run `status` would report any attention item, else 0. So an install that leaves **Test** or **Lint** unfilled, or finds untracked overrides, exits 3 (revision 2 exited 0 for one and 3 for the other). CI onboarding that wants to tolerate this checks for 3 explicitly.

### Verifier alignment (Goal 9)

Today `factory-verifier.md` reads:

```markdown
| Check | Config Key | Required |
|---|---|---|
| Tests | `test_command` | Yes |
| Lint | `lint_command` | Yes |
| Type check | `typecheck_command` | If present |
| Build | `build_command` | If present |

If a config key is empty or marked `none`, skip that check.
...
## Verdict Rules

- **Pass** — ALL checks exit with code 0
- **Fail** — ANY check exits with a non-zero code
...
- If a check command is missing from config, note it as `skipped` (not pass or fail)
```

Changes:

- **Checks table** keyed on the **Commands** labels (**Test**, **Lint** Required; **Type check**, **Build** Optional). A Required row that is missing, empty, `none` or only an HTML-comment placeholder is reported with status `fail` and output "not configured: set **<Label>** in `.ai-factory/config.md` (human action required)". An optional row in any of those states is `skipped`. **Install** and **Format** are not run.
- **Verdict Rules** become: "**Pass** — every Required row is configured and every configured check exits 0. **Fail** — any check exits non-zero, **or any Required row is not configured**."
- The "Important" bullet "If a check command is missing from config, note it as `skipped`" becomes "An optional check that is not configured is `skipped`; a Required check that is not configured is `fail` (not configured)".
- `factory-build` precondition 3 becomes "`.ai-factory/config.md` present **with Test and Lint filled**; otherwise stop and ask the human". **Step C** gains a row placed **first after `pass | pass`**, above `revisions-needed | anything`, `anything | fail` and the mixed row: "anything | **fail**, and any failed check is *not configured* → **stop and ask the human** to fill the missing command in `config.md`; do not append to the task file or re-invoke the Coder". A sentence under the table states that this row **overrides every other row**, whatever the Reviewer verdict, so a first-match reading cannot route the failure to the Coder. This covers config changes mid-loop and manual Verifier runs.
- The `verify.md` template needs no change (`fail` exists).
- The contract test asserts: Verifier labels ⊆ template Commands labels with matching Required rows; the Verdict Rules section contains the not-configured fail rule; the "Important" section has no unconditional `skipped` rule; `factory-build` Step C's **second data row** is the not-configured → human row and the override sentence is present.

### Managed git blocks

The CLI owns exactly one delimited block in `.gitignore` and one in `.gitattributes` (contents in Data Model). `install` and `upgrade` replace each block in place, append it (adding a trailing newline first if needed) when absent, create the file if missing, and rewrite nothing when the block is already identical. **Edits inside a block are replaced without blocking**, the one stated exception to Goal 3: the block is CLI-owned configuration, not a customization point; user rules belong outside the delimiters, which the CLI never touches. The plan line says `update .gitignore (managed block)` so the replacement is visible. Uninstall rules are below.

### Status

`status` is read-only, works offline (except `--remote`), and reports:

- installed version, framework digest match, targets, self-host mode;
- generated files: out of date (rows 2, 5, 6, 9, exec-bit mismatch: "run sync"), lock out of date (row 3/10: "run sync"), edited (rows 4, 7, 11), collisions (row 12);
- overrides: each with kind (replace / append / frontmatter / new) and state (current, untracked, stale with review hint, orphaned);
- **Test** / **Lint** still holding placeholders, empty or `none` in `config.md`;
- a declared `soloaifactory` dependency spec that is not exactly the locked version (Versions and pinning);
- with `--remote`: a newer version on the registry;
- **informational only (never affect the exit code):** unmanaged files inside generated directories and leftover `.ai-factory/framework/` / `.ai-factory/sync.sh` (What lives where). Junk-list files are not reported at all.

Exit precedence: 2 usage, 5 no lock, 4 unparseable lock, symlink, version/digest mismatch or source-repo refusal, 6 invalid overrides, 3 any attention item, else 0.

### Uninstall

`uninstall` needs the lock but not a matching version (it never composes), takes the mutex, plans first (`--dry-run` prints the plan and exits), and confirms interactively. Order:

1. Remove each `gen` file whose disk hash equals its lock hash, or (when the CLI version and digest match the lock) equals the current composed output. Edited files are kept and listed. A `.gitkeep` is removed only if its directory is otherwise empty. Then remove generated directories left empty (one still holding junk-list or unmanaged files stays), and `.cursor/` / `.claude/` themselves if empty.
2. Remove the `.gitattributes` block (delete the file if it is then empty).
3. `.gitignore` block: if `.ai-factory/projects/` or `.ai-factory/archive/` still has content other than `.gitkeep`, or `.ai-factory/.factory-backup/` exists, **rewrite the block to keep only the lines still needed**: the four `projects/*` / `archive/*` lines while either directory has content, and the `.ai-factory/.factory-backup/` line while that directory exists. Print a warning listing what is kept ("these stay gitignored so working Design Docs and backups are not committed by accident; delete the block yourself once you have moved them"). Otherwise remove the block (delete the file if empty). A later `install` replaces the reduced block normally; a later `uninstall` with nothing left removes it.
4. Remove `factory.lock` (last, so an interrupted uninstall can be re-run).
5. Release the mutex; remove `.ai-factory/` if empty.

Kept and listed: `config.md`, `overrides/`, `projects/*`, `archive/*`, `.factory-backup/`, edited generated files, unmanaged files.

### Versioning and release (npm)

- SemVer on `package.json` `version`, the single source of truth (the CLI reads it at run time). Changes to shipped agent, skill or template content bump at least the minor version; wording-only fixes are patches. Breaking changes to the lock format, overrides layout, composition rules, CLI flags, exit-code meanings or the minimum Node version bump the major version.
- **Frozen external contracts**, which scripts and CI parse: (1) the lock `format` and its records; (2) the overrides layout; (3) the lock's **`version` record shape**, `version<TAB><semver>` on its own line, independent of `format`, so the documented CI step keeps working across lock formats; (4) the **exit-code meanings 0–7**. A change to (3) or (4) is a major version and must keep the README CI step working. There is no bootstrap or hand-off contract.
- `CHANGELOG.md` at the repo root (shipped). `upgrade` prints the release-notes URL for its version.
- **`release.yml`**, on a pushed `v*` tag, with workflow-level `permissions: contents: read` (also the ceiling for the called `ci.yml`):
  1. `check` job: assert the tag equals `v` + `package.json` version, that the tagged commit is reachable from `main`, and that `CHANGELOG.md` has a section for that version (before anything is published).
  2. `test` job: call the reusable `ci.yml` (lint, typecheck, full OS × Node test matrix, packaging checks, cross-OS digest equality).
  3. `publish` job, `needs: [check, test]`, `environment: npm-publish` (GitHub environment with required reviewers), job permissions `id-token: write` and `contents: read` (the only job with `id-token`): `npm ci`, then `npm publish --provenance --access public` using **npm trusted publishing**; the trusted-publisher config on npm pins the repository, `release.yml` and the `npm-publish` environment. Versions with a prerelease suffix publish with `--tag next` so `latest` does not move. Trusted publishing needs a recent npm (11.5 or newer at the time of writing); the job installs a pinned npm version.
  4. `notes` job (after publish, job permission `contents: write`): create the GitHub release from the matching `CHANGELOG.md` section. Its failure does not affect the npm artifact.
- **First publish (one time).** npm configures trusted publishing per existing package, so the first version is published by the same `release.yml` run, authenticated by a short-lived granular npm token stored as an `npm-publish` **environment** secret (`NODE_AUTH_TOKEN`); provenance is still generated in CI from the job's OIDC token, so the first version meets Goal 10 too. Immediately afterwards the maintainer configures the trusted publisher (pinned to `npm-publish`), deletes the secret, revokes the token and sets the package to disallow token publishing. The publish step uses the token only when the secret exists. The README's maintainer section holds this runbook.
- **Nothing is published unless every test passes** and a reviewer approves the `npm-publish` environment, and tags are not a distribution channel, so a failed release leaves nothing reachable: the tag can be deleted and re-pushed. No immutable-release or tag-protection precondition is needed; npm itself forbids republishing a version.
- The published `package.json` has no `dependencies` and no lifecycle scripts (`preinstall`, `install`, `postinstall`, `prepare`), asserted by the contract test, so `npx` runs nothing but `bin/soloaifactory.js`. The npm account uses 2FA.

### Repository restructuring (this repo)

```
before                                     after
.ai-factory/framework/agents/*.md          framework/agents/*.md                  (source, ships in the npm package)
.ai-factory/framework/skills/**            framework/skills/**                    (source, ships)
.ai-factory/templates/*.md (edited)        framework/templates/*.md               (source, ships)
                                           .ai-factory/templates/*.md             (generated by the CLI in self-host mode, committed)
.ai-factory/config.md (blank template)     framework/config.template.md           (blank template, ships)
                                           .ai-factory/config.md                  (THIS repo's config: Node, npm test, lint, typecheck)
.ai-factory/sync.sh                        (deleted; replaced by `soloaifactory sync`)
.ai-factory/examples/oauth2/**             examples/oauth2/**                     (repo root, never ships)
(none)                                     package.json, package-lock.json, jsconfig.json
(none)                                     bin/soloaifactory.js, src/**           (the CLI, ships)
(none)                                     scripts/check-src.js                   (lint, never ships)
(none)                                     test/**                                (never ships)
(none)                                     .ai-factory/factory.lock               (this repo's own lock, self-host mode)
(none)                                     test/fixtures/golden-sources/**, golden-adapters/**   (pre-change snapshots)
```

The shipped `factory-archive` skill references `.ai-factory/examples/` (SKILL.md "What you must not touch" row and the matching edge-case row; `reference.md` "based on `.ai-factory/examples/oauth2/`"); those become repo-agnostic. The "Invoking subagents" paragraph in `factory-design`, `factory-plan` and `factory-build` ("generated from `.ai-factory/framework/agents/` by `.ai-factory/sync.sh`") becomes "generated by `soloaifactory sync` from the soloAIfactory package plus `.ai-factory/overrides/`". All adapters are regenerated (the marker text changes in every file).

**Restructuring order** (binding for the plan):

1. **Capture fixtures from the pre-change tree:** the 22 committed adapters (6 agents and 5 skill files, for each tool) to `test/fixtures/golden-adapters/`, and today's `.ai-factory/framework/**` sources to `test/fixtures/golden-sources/`.
2. **Move the sources** (`framework/`, `framework/config.template.md`, `examples/`) and apply the content changes listed in Non-Goals (a)–(d).
3. **In the same commit, delete** the 22 legacy adapters, `.ai-factory/sync.sh`, `.ai-factory/framework/` and the hand-written `projects/*`/`archive/*` lines in `.gitignore`.
4. **Run `node bin/soloaifactory.js install`** (self-host) to generate the adapters, `.ai-factory/templates/` (adopted, row 10, since their content is unchanged), the `.gitkeep` files, the git blocks and the lock; commit the result.

Step 3 keeps the first install free of collisions; the legacy-marker rule (row 11) is the safety net if an adapter is missed, and also helps `cp -r` adopters.

### Removed with the bash model

Everything below existed only because of the bash + `curl | bash` design and is gone: the bootstrap phase and staged re-exec; `--staged`, `--source`, `--repo` and the payload `--version` flag; the `$TMPDIR` staging directory and its cleanup traps; release tarballs, `.sha256` files and the `pack` command; tag-pinned raw-URL invocation and `latest` resolution through GitHub redirects; `FACTORY_REPO`, `FACTORY_DOWNLOAD_BASE`, `FACTORY_SH_LIB`; the immutable-release and tag-protection preconditions; the `PAYLOAD_PATHS` allowlist and the payload decision table (no payload in targets); the "local edit to `framework/` blocks" rule; the bash `chmod 755`/`mode` actions (replaced by exec-bit preservation in Cross-platform rules); locale concerns (`LC_ALL=C`), replaced by the code-unit comparator; the awk renderer and its `ENVIRON`/`substr` escaping rules; the `jq`/awk `package.json` scan; the `.factory-source` marker (replaced by self-host detection); the bash test harness, `shellcheck` and the bash 3.2 macOS job.

### Testing strategy (for the CLI in this repo)

- **Runner:** `node --test "test/**/*.test.js"` (the explicit glob keeps helpers and fixture `.js` files out) with `node:test` and `node:assert/strict`. Unit tests import `src/*` directly; black-box tests spawn `node <package root>/bin/soloaifactory.js` with `cwd` set to a temp target.
- **Isolation:** each test gets a `fs.mkdtempSync(os.tmpdir())` target with a `.git` directory (or a real `git init` where history matters), and `HOME`, `CI` and `NO_COLOR` set explicitly. No network: `status --remote` tests inject the fetch function.
- **Fake releases:** `test/helpers/fake-package.js` copies `package.json`, `bin/`, `src/` and `framework/` into a temp "package root", sets its version (e.g. `0.1.0`, `0.2.0`) and mutates its framework (edit, add, drop or rename an agent). Running two such roots stands in for `npx soloaifactory@0.1.0` and `@0.2.0`.
- **`treeHash`:** SHA-256 over the code-unit-sorted list of every directory path and every file's path, content hash and (on POSIX) exec bit under the target, excluding `.git/`. Directories are included so "creates nothing" is testable.
- **Renderer parity:** in restructuring step 1, today's committed adapters are captured under `test/fixtures/golden-adapters/` and the pre-change sources under `test/fixtures/golden-sources/`; a test feeds `golden-sources/` (not the modified `framework/`) to the Node renderer and asserts it reproduces `golden-adapters/` exactly except for the marker line.
- **Coverage, mapped to Goals:**
  - Goal 1: fresh install per fixture (`node-npm`, `node-pnpm-ts`, `node-no-lint`, `node-npm-init`, `python-uv`, `python-poetry`, `go`, `rust`, `polyglot-prettier-only` (Python wins), `polyglot-two-signals` (placeholders + warning; `--primary` fills), `empty`), with expected exit codes (0 or 3).
  - Goal 2: second `install` and second `sync` → identical tree hash and lock bytes.
  - Goal 3: every row of the generated-file decision table for adapters, templates and `.gitkeep`; edited template / adapter → exit 4, identical tree hash, message names `overrides/`; `--force` backups byte-identical; collisions are refused even with `--force`; `overrides/` and `config.md` byte-identical after upgrade.
  - Goal 4: scenarios (i)–(vi) on `git clone`s; ack-only recording (install/upgrade/sync never write `override` records); orphaned append/frontmatter not ackable; untracked → exit 3; ack of an unknown path → exit 2; frontmatter staleness keyed on the overridden key spans (body edit → current; `model` line edit, upstream adding `model`, or a changed key set → stale); append stale on any base edit.
  - Relock: real `git merge` conflicts (two branches acking different overrides; two upgrades; a diff3-style conflict; a hand merge keeping both sides) → `install --relock` keeps agreeing and one-sided `override` records, makes disagreeing ones untracked, rebuilds `gen` from disk, removes dropped files only when they match a side's hash; version matching neither side → exit 4; unparseable-lock message names `--relock` and `--target`.
  - Goal 5: uninstall order and kept set; `.gitignore` reduced block when `projects/` has content or `.factory-backup/` exists, full removal when nothing is left; uninstall with a different CLI version; a generated directory holding junk stays.
  - Goal 6: `--dry-run`, `status`, `detect`, `show`, `sync --check` on fresh and installed targets → identical tree hash, no `.ai-factory/` created, no prompt even with a TTY-like stdin.
  - Goal 9: contract tests on the Verifier and `factory-build` prompts, including the Step C row position.
  - Goal 10: version-gate table (every cell); digest mismatch from a fake package at the same version with a modified `framework/`, `src/` or `bin/` file, with both message variants (checkout vs packaged); `upgrade --allow-unreleased` warns and re-pins, without it exit 4; `--allow-downgrade`; self-host mode (gates skipped, `upgrade` refused, lock holds `version 0.0.0-self` / `framework self` and stays byte-identical across framework edits); a non-self-host CLI on that lock or on a `package.json` named `soloaifactory` → exit 4 with the `npm run check` advice.
  - Overrides: every composition rule; frontmatter override replacing a folded `description: >` block and adding `model`; `cursor.model`/`claude.model` precedence over `model` per tool, no dotted key in output; frontmatter contract (`name` ≠ stem, missing `description`, `tools` with `readonly: true`, unknown keys passed through, flow syntax rejected); every invalid-layout case → exit 6 with nothing written (install, upgrade, sync, status, ack); junk files in `overrides/` ignored (no exit 6, not copied).
  - Bare `soloaifactory` → usage on stderr, exit 2, tree hash unchanged, even without a TTY.
  - Failure contract: an injected I/O error in APPLY (dependency-injected `fs` in `src/apply.js`; plus a POSIX-only read-only-directory black-box test) → exit 1, lock unchanged, "re-run" message; the re-run exits 0 and writes the lock. Leftover temp files are cleaned.
  - Process: mutex held by a live pid → exit 7; dead pid → reclaimed; `ack` blocked by a held mutex; refused fresh install leaves no `.ai-factory/`.
  - Lock: round trip; unknown record kinds preserved verbatim, after the known kinds sorted by full line; conflict markers (incl. `|||||||`), duplicate paths, bad field count, `format 2` → exit 4; a CRLF lock parses; deterministic bytes when run under `LANG=en_US.UTF-8` and `LC_ALL=C`.
  - Config: renderer round-trips `&&`, `&`, `\`, `|`, `$(…)` and quotes; newline → exit 2; placeholder test script rule; primary selection.
  - Cross-platform (run on all OSes where meaningful): CRLF working-tree files, including `.sh`/`.py` skill files, are not reported as edited; CRLF overrides, `config.md` and frontmatter produce LF output and identical `gen` hashes; a binary skill asset (with NUL) is copied byte for byte; rename retry on a simulated `EPERM`; backslash-free lock paths; case-insensitive duplicate composed paths → exit 6; uppercase unit name → exit 6; case-only rename inside a skill directory keeps the file on a case-insensitive FS (macOS and Windows legs); a symlinked `.claude`, `.claude/skills`, generated skill directory, lock or override → exit 4 with nothing written (POSIX; Windows where symlink creation is permitted) and a symlink-as-file (`core.symlinks=false` shape) → exit 4; exec bit preserved and a lost exec bit reported and fixed by `sync` (POSIX only); self-host detected through a differently-cased path on win32; junk files in generated directories are neither unmanaged nor hashed, and unmanaged files exit 0.
- **Packaging tests:** `npm pack --dry-run --json` lists exactly the `files` allowlist plus npm's always-included `package.json`, `README.md` and `LICENSE` (no `test/`, `examples/`, `.ai-factory/`, `scripts/`); its `framework/` entries equal the CLI's self-host framework scan (junk list applied); framework files committed `100755` keep an exec bit in the tarball; `package.json` has no `dependencies` and no lifecycle scripts; one smoke test runs `npm pack`, then `npx --yes ./soloaifactory-<v>.tgz install` in a temp repo (ubuntu job only).
- **Contract tests:** detector keys ⊆ template labels; Verifier and `factory-build` rules above (Step C row position included); every framework unit name is lowercase and every path is in the allowed character set; no committed framework file matches the junk list; every framework agent and `SKILL.md` frontmatter parses under the subset and the frontmatter contract; no symlinks under `framework/`; the README CI step matches Invocation forms; `src/` and `bin/` import only `node:` modules (also enforced by lint); `version` is valid SemVer; `engines.node` is `>=24`.
- **Cross-OS digest equality:** `test/fixtures/digest-package/` (text with CRLF-prone content, a binary file, nested directories) has its expected digest committed in `test/fixtures/digest-package.sha256`, asserted on every leg; the fixture is committed `-text`, so its CRLF file has the same bytes on every OS and the digest must normalize it identically. In addition each `test` leg prints `node bin/soloaifactory.js version` (which includes the build digest) into an artifact, and a `digest-equal` job fails unless all legs report the same digest.
- **CI (`ci.yml`, reusable via `workflow_call`, workflow-level `permissions: contents: read`):** `lint` (`npm run lint`), `typecheck` (`npm run typecheck`), `self-check` (`npm run check`, the Node equivalent of the old `sync.sh --check`, now also covering templates, overrides and config), `test` on `ubuntu-latest`, `macos-latest` and `windows-latest` × Node 24 and 26, and `digest-equal`.
- **Dogfooding:** this repo's `.ai-factory/config.md` lists JavaScript (ESM) on Node ≥24 with npm; **Test** `npm test`, **Lint** `npm run lint`, **Type check** `npm run typecheck`, **Build** `none`, so the factory's own Verifier can check work on the CLI.

## Data Model Changes

There is no database. The new or changed data structures are files.

### 1. Lock file: `.ai-factory/factory.lock` (committed)

Line-oriented, tab-separated, `#` comments, written with LF line endings (CRLF accepted on read), no timestamp. Records appear in a fixed kind order (`format`, `version`, `framework`, `scope`, `targets`, then `gen` and `override` each sorted by path with the code-unit comparator, then unknown kinds sorted by full line). Rewritten only when its content changes, so re-runs leave it byte-identical.

```
# soloAIfactory install lock - managed by the soloaifactory CLI; do not edit
format	1
version	0.1.0
framework	<sha256>
scope	project
targets	claude cursor
gen	<sha256>	.ai-factory/archive/.gitkeep
gen	<sha256>	.ai-factory/projects/.gitkeep
gen	<sha256>	.ai-factory/templates/design.md
...
gen	<sha256>	.claude/agents/factory-architect.md
gen	<sha256>	.claude/skills/factory-archive/SKILL.md
...
gen	<sha256>	.cursor/skills/factory-plan/SKILL.md
override	<sha256>	0.1.0	.ai-factory/overrides/agents/factory-coder.append.md
override	-	0.1.0	.ai-factory/overrides/agents/my-domain-expert.md
override	<sha256>	0.1.0	.ai-factory/overrides/skills/factory-archive/
```

| Record | Fields | Constraints |
|---|---|---|
| `format` | integer | Lock schema version, `1`. A CLI refuses a greater value |
| `version` | SemVer | Package version that generated the files. **Frozen shape** `version<TAB><semver>`, independent of `format` (read by the CI step). Self-host: `0.0.0-self` |
| `framework` | SHA-256 hex, or `self` | Digest of every packaged file that affects output (§9). Distinguishes a published build from a local one at the same version. Self-host: `self` |
| `scope` | `project` | Only value in v1; reserved for user scope |
| `targets` | space-separated, sorted: `claude`, `cursor` | Used by later `upgrade`/`sync` unless `--target` is given. `all` is stored expanded |
| `gen` | SHA-256 hex (LF-normalized for text files), repo-relative POSIX path | One per generated file |
| `override` | baseline digest or `-`, acked CLI version, repo-relative override path | One per acked override unit (a file, or a replacement skill directory with trailing `/`). Written only by `ack` |
| *(unknown kind)* | any | Preserved verbatim on rewrite, after the known kinds, sorted by full line |

TSV over JSON: each record is one line with no separators shared between lines, so additions on two branches that are not adjacent merge cleanly, whereas a JSON object changes the previous line (the trailing comma). Adjacent changes still conflict; `install --relock` repairs them (Lock failure and recovery). The `version` line is readable in CI with one `node -p` call.

### 2. `.gitignore` managed block (target repo)

```gitignore
# >>> soloAIfactory (managed by the soloaifactory CLI) >>>
.ai-factory/projects/*
!.ai-factory/projects/.gitkeep
.ai-factory/archive/*
!.ai-factory/archive/.gitkeep
.ai-factory/.factory-backup/
.ai-factory/.factory-run/
# <<< soloAIfactory <<<
```

After an uninstall that leaves content in `projects/` or `archive/`, the block keeps only its first four lines, plus the `.ai-factory/.factory-backup/` line while that directory exists (or only that line when `projects/` and `archive/` are empty).

### 3. `.gitattributes` managed block (target repo)

`text=auto` lets git decide per file by content (a NUL byte means binary), matching the CLI's own text rule, so skill scripts of any extension get LF while a binary asset added to an override or a future skill is never corrupted:

```gitattributes
# >>> soloAIfactory (managed by the soloaifactory CLI) >>>
.ai-factory/factory.lock text eol=lf
.ai-factory/overrides/** text=auto eol=lf
.ai-factory/templates/** text=auto eol=lf
.cursor/agents/factory-*.md text eol=lf
.cursor/skills/factory-*/** text=auto eol=lf
.claude/agents/factory-*.md text eol=lf
.claude/skills/factory-*/** text=auto eol=lf
# <<< soloAIfactory <<<
```

The block keeps the repository content consistent; correctness does not depend on it, because hashing normalizes CRLF for every text file (adapters for non-`factory-*` override names, and files git classifies differently from the CLI, are covered by that normalization).

### 4. Working directories in the target (gitignored)

| Path | Purpose | Lifetime |
|---|---|---|
| `.ai-factory/.factory-backup/<UTC YYYYMMDDTHHMMSSZ>/<repo-relative path>` | Copy of an edited generated file saved before a `--force` overwrite or removal | User-managed |
| `.ai-factory/.factory-run/` | Mutex; file `owner` holds `<pid> <hostname>`. Created only by write runs | One run |

### 5. Overrides directory (user-owned, committed)

Layout and composition rules as in "Overrides composition". The CLI never creates, writes or deletes anything here.

**`<name>.frontmatter.yml` grammar** (a restricted YAML subset, parsed by `src/yaml-subset.js`, ~100 lines, the same reader used for all agent and skill frontmatter: framework, replacement and new; input CRLF-normalized first). YAML rather than JSON because it is the syntax of the frontmatter it edits (users copy lines across unchanged) and because multi-line `description:` blocks are unreadable as JSON strings.

- One mapping of top-level `key: value` entries; keys match `([a-z]+\.)?[a-z][a-z0-9_-]*` at column 0 (the dotted form only as `cursor.model` / `claude.model`); full-line `#` comments and blank lines are allowed, including blank lines inside a block scalar.
- A value is a plain scalar on one line (not starting with any of ``{ [ & * ! | > ' " % @ ` ``, and **not containing `: ` or ` #`**, which real YAML parsers reject or truncate; the error says "quote this value"), a single- or double-quoted scalar on one line, or a block scalar introduced by `>`, `>-`, `|` or `|-` followed by one or more lines indented with spaces.
- Not allowed: tabs for indentation, flow collections, anchors/aliases/tags, multiple documents, nested mappings, duplicate keys.
- Allowed keys in `.frontmatter.yml` in v1: `model`, `cursor.model`, `claude.model` (each a non-empty plain or quoted scalar), `description` (any scalar form). Precedence per tool: `<tool>.model` > `model` > the base's `model`. Agent and skill files follow the frontmatter contract in Overrides composition.

Example (Cursor keeps `inherit`, Claude Code uses `sonnet`):

```yaml
model: inherit
claude.model: sonnet
description: >
  Implements a single task for the payments service. Follows our
  hexagonal architecture rules.
```

### 6. Generated files

| Path | Source | Marker |
|---|---|---|
| `.<tool>/agents/<name>.md` | Composed agent, rendered per tool | Yes, after frontmatter |
| `.<tool>/skills/<name>/<file>` | Composed skill; `.md` files rendered with marker, others copied (exec bit preserved on POSIX) | `.md` files only |
| `.ai-factory/templates/<name>` | Composed template | No |
| `.ai-factory/projects/.gitkeep`, `.ai-factory/archive/.gitkeep` | Empty files | No |

Text files are written with LF line endings, binary files byte for byte; all are tracked by `gen` records.

### 7. Detection keys (internal)

| Key | `framework/config.template.md` label | Section |
|---|---|---|
| `language`, `runtime`, `framework`, `package_manager` | Language, Runtime, Framework, Package Manager | Tech Stack (bullets) |
| `source_dir`, `test_dir`, `entry_point`, `config_files` | Source directory, Test directory, Entry point, Config files | Project Structure (bullets) |
| `install`, `test`, `lint`, `typecheck`, `build`, `format` | Install, Test, Lint, Type check, Build, Format | Commands (table, cell 2) |
| `code_style` | Code style | Conventions (bullets) |

The same keys are accepted by `--set KEY=VALUE`. Unknown keys are a usage error (exit 2).

### 8. npm package manifest (`package.json`)

```json
{
  "name": "soloaifactory",
  "version": "0.1.0",
  "description": "Install and manage the soloAIfactory agent workflow in a repository",
  "type": "module",
  "bin": { "soloaifactory": "bin/soloaifactory.js" },
  "files": ["bin/", "src/", "framework/", "CHANGELOG.md", "LICENSE"],
  "engines": { "node": ">=24" },
  "repository": { "type": "git", "url": "git+https://github.com/<owner>/<repo>.git" },
  "license": "<see Open Questions>",
  "publishConfig": { "access": "public", "provenance": true },
  "scripts": {
    "test": "node --test \"test/**/*.test.js\"",
    "lint": "node scripts/check-src.js",
    "typecheck": "tsc -p jsconfig.json",
    "sync": "node bin/soloaifactory.js sync",
    "check": "node bin/soloaifactory.js status"
  },
  "devDependencies": { "typescript": "<exact version>" }
}
```

No `dependencies`, no `main`/`exports`, no lifecycle scripts. `repository.url` must match the publishing repository for provenance.

### 9. Framework digest

SHA-256 over the code-unit-sorted lines `<POSIX path relative to the package root>\t<sha256>\n` for every file under the package's `framework/`, `src/` and `bin/` (everything packaged that affects output; junk-list files skipped), where the inner hash is over LF-normalized bytes for text files and raw bytes for binary files. Paths are built with `/` by the CLI, never from `path.relative`, so every OS computes the same value (asserted cross-OS in CI). File modes are excluded. The lock record keeps the name `framework`. Computed at run time; recorded in the lock (`self` in self-host mode); compared by the version gate; printed by `version`.

### 10. Config template

`framework/config.template.md` holds today's `.ai-factory/config.md` unchanged; its labels are the contract for the renderer, the Verifier and the contract test. `.ai-factory/config.md` in this repo becomes a filled, repo-specific config.

## API Surface Changes

The new public API is the command line of the `soloaifactory` npm package. No HTTP endpoints, events or programmatic API. `sync.sh` and its flags are removed.

### Invocation forms

```bash
# Install (any repo, Node 24+ on this machine). Only an explicit `install` installs;
# a bare `npx soloaifactory` prints usage and exits 2.
npx --yes soloaifactory@latest install      # resolves latest once (no --prefer-offline, so it is fresh); the lock then pins it
npx --yes soloaifactory@0.1.0 install       # explicit version

# Day to day, always at the locked version (the CLI prints this form on any mismatch)
npx --yes --prefer-offline soloaifactory@0.1.0 sync      # after editing .ai-factory/overrides/
npx --yes --prefer-offline soloaifactory@0.1.0 status
npx --yes --prefer-offline soloaifactory@0.1.0 ack .ai-factory/overrides/agents/factory-coder.md
npx --yes --prefer-offline soloaifactory@0.1.0 detect > config.proposal.md
npx --yes --prefer-offline soloaifactory@0.1.0 show agents/factory-coder.md
npx --yes --prefer-offline soloaifactory@0.1.0 uninstall --dry-run
npx --yes --prefer-offline soloaifactory@0.1.0 install --relock --target claude   # after a lock merge conflict

# Upgrade: run the NEW version's upgrade
npx --yes soloaifactory@latest upgrade
npx --yes soloaifactory@0.2.0 upgrade

# Optional, Node repos: pin as a devDependency, then drop the @version
npm install --save-dev --save-exact soloaifactory@0.1.0
npx soloaifactory status

# Contributors, inside this repo (self-host mode)
npm run sync    # node bin/soloaifactory.js sync
npm run check   # node bin/soloaifactory.js status
```

**Target-repo CI step** (documented in README; after `actions/setup-node` with `node-version: 24`). It reads the frozen `version` line with Node instead of `awk` (CRLF-safe), and `shell: bash` makes it run unchanged on Windows runners, whose default shell is pwsh; on other CI systems run it in any POSIX shell:

```yaml
- name: soloAIfactory status
  shell: bash
  run: npx --yes --prefer-offline "soloaifactory@$(node -p "require('fs').readFileSync('.ai-factory/factory.lock','utf8').match(/^version\t([^\r\n]+)/m)[1]")" status
```

### Commands

| Command | Purpose | Lock needed | Version gate | Writes | Mutex |
|---|---|---|---|---|---|
| `install` | Fresh install, adopt, or same-version reconcile; renders `config.md` if absent; manages git blocks; `--relock` repairs a conflicted lock. Never implied: no command prints usage and exits 2 | No | Yes | Yes | Yes |
| `upgrade` | Move the install to the running CLI's version (or reconcile at the same version) | Yes | Upgrade rules | Yes | Yes |
| `sync` | Regenerate adapters, templates and scaffolding at the locked version (after editing overrides); `--check` reports staleness read-only | Yes | Yes | Yes (not with `--check`) | Yes (not with `--check`) |
| `status` | Read-only health report | Yes | Yes | Never | No |
| `ack <path>…` | Record the current base digest as reviewed for each named override (file, or replacement skill directory; a path inside a skill directory is normalized to its unit) | Yes | Yes | Lock only | Yes |
| `detect` | Print a rendered config proposal to stdout | No | No | Never | No |
| `show <framework path>` | Print a framework file (or each file of a skill directory, with headers) from the running package, for reviewing upstream changes. The argument is looked up in the package's scanned file list (exact POSIX match, or a skill directory prefix), never joined onto a filesystem path; anything else is exit 2 | No | No | Never | No |
| `uninstall` | Remove what the lock says the CLI generated, in the documented order | Yes | No (format only) | Yes | Yes |
| `version` | Print the CLI version and its build digest, and the installed version if a lock exists | No | No | Never | No |

`ack` details: a path that is not an existing override unit under `.ai-factory/overrides/` (unknown, outside the directory, or not a valid unit) is a usage error (exit 2) and nothing is written; an override that is already current prints "already current" and is a no-op; an orphaned append or frontmatter override is refused with exit 2 ("delete or retarget it; it cannot be acked"). `ack` validates the whole overrides layout first (exit 6). `ack` never regenerates files.

### Flags

| Flag | Applies to | Default | Meaning |
|---|---|---|---|
| `--dir DIR` | all except `show`, `version` | nearest ancestor with `.git`, else cwd | Target repository |
| `--target cursor\|claude\|all` | install, upgrade, sync | install: `all`; upgrade/sync: the lock's `targets` | Which adapters to generate; a shrink removes the dropped tool's pristine adapters |
| `--dry-run` | install, upgrade, sync, uninstall | off | Print the plan, write nothing, never prompt. Exits 0 if the run would proceed, else the refusal code (4, 5, 6; 7 cannot occur because a dry run takes no mutex) |
| `--relock` | install | off | Leniently parse a conflicted or hand-merged lock and rebuild it, keeping agreeing `override` records (Lock failure and recovery). On a parseable lock, same as plain `install` |
| `--check` | sync | off | Read-only; exit 3 if any generated file or the lock is out of date |
| `--yes` / `--non-interactive` | install, upgrade, uninstall | auto (on when `CI` is set or no TTY) | No prompts; accept defaults |
| `--force` | install, upgrade, sync | off | Back up and overwrite or remove edited generated files. Never applies to collisions |
| `--allow-downgrade` | upgrade | off | Permit moving to an older version than the lock's |
| `--allow-unreleased` | upgrade | off | Permit re-pinning the lock to this build when it has the lock's version but a different digest; prints a warning naming both digests |
| `--set KEY=VALUE` (repeatable) | install, detect | none | Supply or override a config value (keys per Data Model §7) |
| `--primary node\|python\|go\|rust` | install, detect | auto | Choose the primary ecosystem for Commands |
| `--no-config` | install | off | Do not create `config.md` |
| `--remote` | status | off | Compare against the registry's latest version |
| `--verbose` | all | off | Also print `skip` plan lines |
| `-h`, `--help`; `-v`, `--version` | all | | Usage; print the CLI version |

`sync` never prompts (it never overwrites an edit without `--force`).

### Environment variables

| Variable | Effect |
|---|---|
| `CI` | Any non-empty value implies non-interactive |
| `NO_COLOR` | Disable ANSI color |
| `npm_config_registry` | Registry used by `status --remote` (default `https://registry.npmjs.org/`); `.npmrc` files are not read |
| `NODE_USE_ENV_PROXY`, `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY` | Node's own proxy support for `status --remote`: the proxy variables apply only when `NODE_USE_ENV_PROXY=1` |

### Exit codes

The meanings below are a frozen external contract (Versioning and release).

| Code | Meaning |
|---|---|
| 0 | Success; nothing needs attention |
| 1 | Runtime error: I/O failure during APPLY (lock not written; re-run to finish), registry error for `status --remote`, Node older than 24, unexpected exception |
| 2 | Usage error: no command, unknown command, flag or key; bad `--target`/`--primary`; value containing a newline; `ack` path that is not an override unit or is an orphaned append/frontmatter; `show` path not in the packaged file list |
| 3 | Completed, attention needed. One rule for every command: exit 3 when the post-run `status` would report any attention item (unfilled Test/Lint, untracked/stale/orphaned overrides, out-of-date or edited generated files, a declared dependency spec other than the exact locked version, newer release with `--remote`). Unmanaged files, leftovers and junk files never cause it. `sync --check`: generated files or lock out of date |
| 4 | Refused before writing, permanently until the user acts: edited generated files without `--force`; adapter collision; version or framework-digest mismatch (same-version re-pin without `--allow-unreleased`); downgrade without `--allow-downgrade`; `install` would change the installed version; `upgrade` in self-host mode; source-repo lock or package outside self-host mode; a symlink under a managed path or `overrides/`; `--relock` with a version matching neither side; lock unparseable or `format` too new |
| 5 | No lock: `upgrade`, `sync`, `status`, `ack`, `uninstall` on a directory that has never been installed |
| 6 | Invalid overrides layout or frontmatter contract violation (including non-lowercase unit names and case-insensitive duplicate paths), detected before any write (`install`, `upgrade`, `sync`, `status`, `ack`) |
| 7 | Busy (transient): another run holds the mutex; nothing was written; safe to retry |

### Output contract

Human-readable plan lines, one per action: `<action> <path>` with action in {`add`, `update`, `adopt`, `restore`, `remove`, `drop`, `chmod`, `blocked`, `collision`, `backup`, `skip`}; `--relock` adds `keep-ack` and `untrack` lines for override records. Informational `status` lines are prefixed `info`. `skip` lines are hidden unless `--verbose`. Warnings and errors go to stderr prefixed `soloaifactory:`.

## File Impact Map

| File | Action | Description |
|---|---|---|
| `package.json` | create | Manifest per Data Model §8: name, version, `type: module`, `bin`, `files` allowlist, `engines.node >=24`, `repository`, `license`, `publishConfig` (public, provenance), scripts (`test` = `node --test "test/**/*.test.js"`, `lint`, `typecheck`, `sync`, `check`), `typescript` as the only devDependency; no `dependencies`, no lifecycle scripts |
| `package-lock.json` | create | Lockfile for the devDependency (not shipped) |
| `jsconfig.json` | create | `checkJs`, `strict`, `noEmit`, `module`/`target` for Node 24, includes `bin/`, `src/`, `test/`, `scripts/` |
| `bin/soloaifactory.js` | create | Shebang `#!/usr/bin/env node`; Node-version check written in syntax old Node can parse (exit 1 with a clear message below 24); imports `src/cli.js` |
| `src/cli.js` | create | `util.parseArgs` per command, help text (bare invocation → usage on stderr, exit 2), dispatch, mapping of typed errors to exit codes 1–7, `soloaifactory:` stderr prefix |
| `src/paths.js` | create | Target resolution (walk up for `.git`), package-root resolution, self-host detection (`realpathSync.native`, win32 case-fold), local-checkout detection, repo-relative POSIX path handling, allowed-character and lowercase unit-name validation, the single code-unit comparator |
| `src/fs-policy.js` | create | Junk-file ignore list; symlink checks (`lstat` of managed paths, their parents and `overrides/`; symlink-as-file detection); case-insensitive duplicate detection; exec-bit expectations (skipped on win32) |
| `src/hash.js` | create | SHA-256 helpers, content-based text detection (valid UTF-8, no NUL), CRLF→LF normalization for every text input, directory digests over POSIX paths, frontmatter key-span digests |
| `src/framework.js` | create | Scan the package (`framework/`, `src/`, `bin/`; junk skipped; text normalized, binary verbatim), framework digest (Data Model §9), base lookup and base digests for overrides, the packaged file list for `show` |
| `src/yaml-subset.js` | create | Restricted YAML subset reader (Data Model §5: dotted per-tool model keys, plain-scalar `: `/` #` rejection) with line-numbered errors; locate a key's line span in frontmatter |
| `src/overrides.js` | create | Scan `.ai-factory/overrides/` (junk skipped), classify units (replace / append / frontmatter / new), validate the layout and the frontmatter contract (exit 6), map each unit to its base, compute override states (current, untracked, stale, orphaned) with key-span bases for frontmatter overrides |
| `src/render.js` | create | Port of `sync.sh` `render_agent` / `render_skill_file`: per-tool frontmatter mapping (Cursor `readonly` passthrough, `shell` dropped; Claude `tools:` allowlist), per-tool model resolution (`<tool>.model` > `model`, no dotted keys emitted), marker insertion, line-based frontmatter override application, append joining |
| `src/compose.js` | create | Build the expected output Map<path, {bytes, mode}> for the selected targets: agents, skills, templates, `.gitkeep` scaffolding; case-insensitive duplicate check |
| `src/lock.js` | create | Parse (CRLF-normalized; unparseable rules, `format` check, duplicates, conflict markers incl. `\|\|\|\|\|\|\|`, `framework self`), lenient two-sided parse for `--relock`, serialize (fixed kind order, sorted, unknown kinds after known kinds by full line), equality check to skip rewrites |
| `src/plan.js` | create | Generated-file decision table (rows 1–12, legacy marker, case-only pairing, exec-bit `chmod`), collision and blocked detection, removal of dropped targets, relock merge of `override` records, uninstall plan, status classification (attention vs informational) |
| `src/apply.js` | create | Backups, atomic temp-file + rename writes (mode `0o755` when expected; case-only rename) with Windows `EPERM`/`EBUSY` retry, removals, empty-dir cleanup, temp-file leftovers cleanup, lock-last ordering, failure contract (exit 1, "re-run"); `fs` injectable for tests |
| `src/mutex.js` | create | `.ai-factory/.factory-run/` acquire / reclaim (same host, dead pid) / release (held → exit 7), signal handlers, removal of a `.ai-factory/` created only for the mutex |
| `src/gitblocks.js` | create | Managed `.gitignore` / `.gitattributes` blocks: replace, append, create, remove, reduced uninstall block (keeps `.factory-backup/` line while it exists) |
| `src/detect/index.js` | create | Run detectors, test signals, primary-ecosystem selection (`--primary`, single signal, ambiguity → placeholders + warning), precedence (`--set` > scripts > Makefile > defaults) |
| `src/detect/node.js` | create | `package.json` via `JSON.parse`, package manager from lockfiles, placeholder test-script rule, TypeScript and Prettier detection |
| `src/detect/python.js` | create | `pyproject.toml` line scanner (tables, simple keys), `requirements*.txt`, uv/poetry/pip, pytest/ruff/flake8/mypy/black signals |
| `src/detect/go.js` | create | `go.mod` `go` directive, `.golangci.y*ml` |
| `src/detect/rust.js` | create | `Cargo.toml` edition, `rust-toolchain*` |
| `src/detect/makefile.js` | create | `test`/`lint`/`build` target detection |
| `src/config-render.js` | create | Label-keyed rendering of `framework/config.template.md` (bullets and table cell 2, `\|` escaping, newline rejection, `none` for optionals, placeholders + warnings for Test/Lint) |
| `src/prompt.js` | create | Interactivity detection (TTY, `CI`, `--yes`), `readline/promises` prompts, color with `NO_COLOR` |
| `src/commands/reconcile.js` | create | Shared pipeline for `install`, `upgrade` and `sync`: lock (or `--relock`), version gate (digest messages, `--allow-unreleased`, source-repo refusal), validate, compose, plan, refuse, config (install), plan output, confirm, apply, summary, exit 0/3 |
| `src/commands/status.js` | create | Read-only report and exit precedence; informational lines; declared devDependency spec check; `--remote` registry fetch (injectable; proxy/registry limits in the error message) |
| `src/commands/ack.js` | create | Path validation and normalization, baseline recording, no-op and orphan handling, mutex, lock-only write |
| `src/commands/detect.js` | create | Print the rendered config proposal |
| `src/commands/show.js` | create | Print packaged framework files, resolving the argument only against the packaged file list |
| `src/commands/uninstall.js` | create | Uninstall order, kept set, reduced `.gitignore` block, lock last |
| `src/commands/version.js` | create | CLI version, build digest, installed version |
| `framework/agents/factory-architect.md`, `factory-coder.md`, `factory-evaluator.md`, `factory-planner.md`, `factory-reviewer.md` | create | Moved verbatim from `.ai-factory/framework/agents/` |
| `framework/agents/factory-verifier.md` | create | Moved from `.ai-factory/framework/agents/` and changed: Checks table keyed on Commands labels; Required not configured → `fail` "not configured (human action required)"; optional → `skipped`; Install/Format not run; Verdict Rules "Fail if any check exits non-zero **or any Required row is not configured**"; "Important" skipped bullet rewritten |
| `framework/skills/factory-build/SKILL.md` | create | Moved and changed: precondition 3 requires Test and Lint filled, else stop for the human; Step C row "Verifier fail with *not configured* → stop and ask the human; do not route to the Coder" placed first after `pass \| pass`, plus a sentence that it overrides every other row; "Invoking subagents" paragraph no longer names `.ai-factory/framework/` / `sync.sh` |
| `framework/skills/factory-design/SKILL.md`, `framework/skills/factory-plan/SKILL.md` | create | Moved; "Invoking subagents" paragraph reworded to "generated by `soloaifactory sync` from the soloAIfactory package plus `.ai-factory/overrides/`" |
| `framework/skills/factory-archive/SKILL.md` | create | Moved; `.ai-factory/examples/` row in "What you must not touch" and the matching edge-case row made repo-agnostic |
| `framework/skills/factory-archive/reference.md` | create | Moved; "based on `.ai-factory/examples/oauth2/`" reworded so it does not point at a path absent from installs |
| `framework/templates/design.md`, `epic.md`, `evaluation.md`, `review.md`, `task.md`, `verify.md` | create | Template sources moved from `.ai-factory/templates/` (content unchanged) |
| `framework/config.template.md` | create | Blank config template, moved verbatim from today's `.ai-factory/config.md` |
| `.ai-factory/sync.sh` | delete | Replaced by `soloaifactory sync` |
| `.ai-factory/framework/agents/*.md` (6 files) | delete | Moved to `framework/agents/` |
| `.ai-factory/framework/skills/factory-archive/SKILL.md`, `factory-archive/reference.md`, `factory-build/SKILL.md`, `factory-design/SKILL.md`, `factory-plan/SKILL.md` | delete | Moved to `framework/skills/` |
| `.ai-factory/templates/design.md`, `epic.md`, `evaluation.md`, `review.md`, `task.md`, `verify.md` | modify | Become CLI output in self-host mode (content unchanged), hash-tracked in the lock, no longer edited by hand |
| `.ai-factory/projects/.gitkeep`, `.ai-factory/archive/.gitkeep` | modify | Content unchanged; now generated scaffolding tracked in the lock |
| `.ai-factory/config.md` | modify | This repo's real config: JavaScript (ESM), Node ≥24, npm; Test `npm test`, Lint `npm run lint`, Type check `npm run typecheck`, Build `none`; notes on `npm run sync` / `npm run check` |
| `.ai-factory/factory.lock` | create | This repo's own lock (self-host mode) |
| `.ai-factory/examples/oauth2/00-design.md`, `evaluations/00-design-evaluation.md`, `tasks/T001-add-oauth-providers.md` | delete | Moved to `examples/oauth2/` |
| `examples/oauth2/00-design.md`, `tasks/T001-add-oauth-providers.md` | create | Relocated examples (content unchanged); not in the npm package |
| `examples/oauth2/evaluations/00-design-evaluation.md` | create | Relocated; its Metadata `Design Doc` path changes from `.ai-factory/examples/oauth2/00-design.md` to `examples/oauth2/00-design.md`, otherwise unchanged |
| `.cursor/agents/*.md`, `.claude/agents/*.md` (6 each) | delete, then create | Deleted in the restructuring commit (step 3), regenerated by the CLI install (step 4): new marker text in every file; `factory-verifier.md` content changes |
| `.cursor/skills/**`, `.claude/skills/**` (5 files each) | delete, then create | Same: new marker text in every file; content changes in `factory-archive` (both files), `factory-build`, `factory-design`, `factory-plan` |
| `.gitignore` | modify | Hand-written `projects/*` / `archive/*` lines replaced by the managed block (written by `install` in self-host mode); add `node_modules/` and `*.tgz` |
| `.gitattributes` | create | Managed block, plus repo rules: `framework/** text=auto eol=lf`, `src/**/*.js`, `bin/**/*.js` text `eol=lf`, `test/** text=auto eol=lf`, and `test/fixtures/digest-package/** -text` so the fixture's CRLF bytes are identical on every OS |
| `scripts/check-src.js` | create | Lint: `src/` and `bin/` import only `node:` modules; bans `localeCompare`, `Intl.Collator`, `child_process`, `path.relative` in digest/lock code paths, `process.exit` outside `src/cli.js` and `bin/`; no `dependencies` or lifecycle scripts in `package.json` |
| `test/helpers/tmp-repo.js` | create | Temp targets (`.git` dir or `git init`), env isolation, committed-tree clone helper (uses the git binary; tests only) |
| `test/helpers/tree-hash.js` | create | `treeHash` (dirs + content + POSIX exec bit, code-unit sorted, excluding `.git/`) |
| `test/helpers/fake-package.js` | create | Build versioned fake package roots with mutated `framework/`, `src/` or `bin/` |
| `test/helpers/run-cli.js` | create | Spawn `node <root>/bin/soloaifactory.js` and capture exit code, stdout, stderr |
| `test/install.test.js` | create | Fixtures and exit codes (Goal 1), idempotency (Goal 2), dry-run on fresh/installed targets (Goal 6), git blocks create/append/replace/no-trailing-newline and silent in-block replacement, refused fresh install leaves nothing, adopt incl. legacy-marker adapters (row 11), bare command → exit 2 writes nothing, non-interactive with no TTY |
| `test/upgrade.test.js` | create | Version moves, decision-table rows across versions, dropped/renamed agents, `--allow-downgrade` (unknown lock kinds preserved), `--allow-unreleased`, target shrink, overrides and `config.md` untouched, devDependency hint |
| `test/sync.test.js` | create | Regeneration after override edits, `--check` (exit 3), edited template/adapter blocked (exit 4) and `--force` backups, collisions refused with and without `--force` |
| `test/decision-table.test.js` | create | Unit tests for every row (1–12) in `src/plan.js` |
| `test/overrides.test.js` | create | Composition rules incl. frontmatter overrides on folded blocks and per-tool model keys; frontmatter contract; invalid layouts → exit 6 with nothing written; junk ignored; orphan handling |
| `test/drift.test.js` | create | Goal 4 scenarios (i)–(v) on git clones, key-span frontmatter staleness, whole-file append staleness, ack-only recording, untracked → exit 3, lock deletion → untracked |
| `test/relock.test.js` | create | Goal 4 (vi) and every `--relock` rule on real `git merge` conflicts (two-way, diff3, hand-merged duplicates); message names `--relock` and `--target` |
| `test/fs-policy.test.js` | create | Junk list in overrides, framework and generated dirs; unmanaged files informational (exit 0); lowercase names and case-insensitive duplicates (exit 6); case-only rename; symlinks and symlink-as-file (exit 4); exec bits (POSIX); self-host case-folding (win32) |
| `test/ack.test.js` | create | Unknown/outside path → exit 2, path normalization to skill unit, already-current no-op, orphaned append refused, mutex held → exit 7, version mismatch → exit 4 |
| `test/status.test.js` | create | Read-only (tree hash), each attention item → exit 3, informational items → exit 0, declared-spec devDependency rule, exit precedence, `--remote` with injected fetch |
| `test/uninstall.test.js` | create | Order (generated files, blocks, lock last), kept set, reduced `.gitignore` block when `projects/` has content or `.factory-backup/` exists, works with a different CLI version |
| `test/version-gate.test.js` | create | Every cell of the version table, both digest-message variants, `--allow-unreleased`, self-host sentinels and source-repo refusal |
| `test/digest.test.js` | create | Digest over `framework/`, `src/`, `bin/` with POSIX paths; text vs binary hashing; committed fixture digest equality on every OS |
| `test/lock.test.js` | create | Round trip, fixed order, unknown kinds after known kinds, CRLF lock parses, unparseable cases → exit 4, cross-locale byte equality |
| `test/apply-failure.test.js` | create | Injected I/O failure → exit 1, lock unchanged, message; re-run completes; temp-file cleanup; POSIX read-only-dir variant |
| `test/mutex.test.js` | create | Live holder → exit 7, dead pid reclaimed, release on error and signal |
| `test/detect.test.js` | create | Detector output per fixture, placeholder test script, test signals, primary selection, `--primary`, precedence, `detect` writes nothing |
| `test/config-render.test.js` | create | Label-keyed rendering; `&&`, `&`, `\`, `\|`, `$(…)`, quotes round-trip; newline → exit 2; `none` for optionals; placeholders for unfilled Test/Lint |
| `test/yaml-subset.test.js` | create | Accepted forms (plain, quoted, `>`, `>-`, `\|`, `\|-`, blank lines in block scalars, dotted per-tool keys), rejected forms with line numbers (incl. `: ` and ` #` in plain scalars) |
| `test/render.test.js` | create | Golden parity: `golden-sources/` rendered → `golden-adapters/` (marker line excepted); marker format; per-tool mapping and model resolution |
| `test/crlf.test.js` | create | CRLF working-tree files (incl. non-`.md` skill files) not reported as edited; CRLF inputs (overrides, config, frontmatter, lock); binary verbatim; LF output; Windows rename retry (simulated) |
| `test/packaging.test.js` | create | `npm pack --dry-run --json` equals the allowlist; its `framework/` entries equal the self-host scan; exec bits kept; no `dependencies`/lifecycle scripts; tarball `npx` smoke install (ubuntu only) |
| `test/contract.test.js` | create | Detector keys ⊆ template labels; Verifier labels/Required rows, not-configured verdict rule and no unconditional skip; `factory-build` Step C row in second position with the override sentence; framework unit names lowercase and paths in the allowed charset; no junk or symlinks in `framework/`; framework frontmatter parses under the subset and contract; README CI step; SemVer; `engines.node` |
| `test/fixtures/projects/node-npm/…`, `node-pnpm-ts/…`, `node-no-lint/…`, `node-npm-init/…`, `python-uv/…`, `python-poetry/…`, `go/…`, `rust/…`, `polyglot-prettier-only/…`, `polyglot-two-signals/…`, `empty/…` | create | Minimal marker files (`package.json` variants incl. minified and `npm init` default, lockfiles, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Makefile`) |
| `test/fixtures/golden-adapters/.cursor/**`, `test/fixtures/golden-adapters/.claude/**` | create | Snapshot of today's 22 committed `sync.sh` adapters (restructuring step 1) |
| `test/fixtures/golden-sources/agents/**`, `test/fixtures/golden-sources/skills/**` | create | Snapshot of today's `.ai-factory/framework/**` (restructuring step 1), the renderer input for golden parity |
| `test/fixtures/digest-package/**`, `test/fixtures/digest-package.sha256` | create | Small package tree (text, binary, nested dirs) and its expected digest, asserted on every OS |
| `.github/workflows/sync-check.yml` | delete | Replaced by `ci.yml` |
| `.github/workflows/ci.yml` | create | On PR and push to main, and `workflow_call`; workflow-level `permissions: contents: read`: `lint`, `typecheck`, `self-check` (`npm run check`), `test` matrix ubuntu/macos/windows × Node 24/26 (each leg uploads its build digest), `digest-equal`, packaging tests |
| `.github/workflows/release.yml` | create | On `v*` tag; workflow-level `permissions: contents: read`: `check` (tag == version, on `main`, CHANGELOG section present); call `ci.yml`; `publish` in `environment: npm-publish` (required reviewers), the only job with `id-token: write`: `npm publish --provenance --access public` via trusted publishing, or via the one-time `NODE_AUTH_TOKEN` environment secret for the first publish, pinned npm, `--tag next` for prereleases; then `notes` (`contents: write`) creates the GitHub release from `CHANGELOG.md` |
| `CHANGELOG.md` | create | Per-version changes, starting at the first release; shipped in the package; a section per released version is enforced by `release.yml` `check` |
| `LICENSE` | create | License text per Open Question 4; shipped in the package |
| `README.md` | modify | Rewrite Quick Start around `npx soloaifactory@<v> install` (Node 24+ needed only to run the CLI); "Configure your project" around detection and `detect`; replace "`sync.sh` usage" with "CLI usage" (commands, flags, exit codes, pinned invocation, devDependency option, offline/npx cache, target-repo CI step); "Project-level vs user-level" (project only in v1); replace "Customizing for Your Project" (Agent Prompts, Templates, Adding New Agents) with the overrides model (replace, append, frontmatter, templates, new agents/skills), `ack`, `show` and the review flow; "Project Structure" (target layout vs source-repo layout: `framework/`, `bin/`, `src/`, `test/`, root `examples/`); "Canonical frontmatter" location; all links to `.ai-factory/framework/skills/...` → `framework/skills/...`; the archive section's Git paragraph (managed block); File Reference for `config.md` (labels instead of `test_command`/`lint_command`, Verifier fails on unfilled Required) and for skills; "Requirements" (Node 24+ and npm for the CLI; nothing for using the factory); "Troubleshooting" (status, version and digest mismatch, `install --relock` after a lock conflict, exit 7 retry, symlinks and `core.symlinks`, `status --remote` behind a proxy or private registry, "re-run after a failed apply"); target-repo CI step with `shell: bash`; frozen contracts (lock `version` line, exit codes); "Releasing (maintainers)" runbook incl. the one-time first publish |

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| npm supply chain: a compromised maintainer account or CI publishes a malicious version | high | Trusted publishing (OIDC, no long-lived token); provenance attestation linking each version to a commit and `release.yml` run; npm 2FA; publish only after the full matrix passes on a tag reachable from `main`; no lifecycle scripts and no dependencies (contract test), so nothing runs at install time and no transitive packages exist; versions are immutable and the lock pins an exact version, so an existing install never moves without `upgrade`; `npm audit signatures` documented for devDependency users |
| Requiring Node 24+ excludes users without Node (common in Python, Go and Rust shops) | medium | Needed only by whoever runs the CLI and by CI that runs `status`; using the factory stays plain Markdown; `bin` prints a clear version message; README states the requirement up front; other channels can wrap the package later (Non-Goal) |
| Package name `soloaifactory` unavailable or squatted on npm, or typosquats appear | medium | Resolve before the first publish (Open Question 1); every documented command uses the exact name; README links to the npm page and provenance |
| Version-pinned invocations are long and users run an unpinned `npx soloaifactory` | medium | Version gate refuses with exit 4 and prints the exact pinned command; CI one-liner reads the lock; devDependency option makes `npx soloaifactory` resolve locally |
| Silent loss of user customizations | high | Customizations live in `overrides/` and `config.md`, which no command writes; edited generated files block before any write (exit 4); `--force` always backs up first; tests assert byte-identical overrides and backups |
| Upstream fixes silently never reach a customized agent (replacement drifts) | medium | Ack-only baselines in the committed lock; untracked, stale and orphaned overrides are attention items on every clone and in CI; `status` prints review commands using `show`; frontmatter overrides and appends reduce the need for full replacements |
| Overrides are coarse: appends only add at the end, so prompt-body changes need full replacements that drift | medium | Re-rated from low: `.frontmatter.yml` covers `model`/`description`; drift is visible and reviewable with `show`; README recommends append/frontmatter over replacement; finer-grained composition (per-section) can be added without a lock format change |
| A replacement of an agent that upstream renamed becomes silently unused | medium | Orphaned replacements are attention items until acked or moved; the status hint names the likely rename |
| Users edit generated adapters or `.ai-factory/templates/` out of habit | medium | Edits block the next write run with a "move into `overrides/`" message; `--force` backs up; marker text points to `overrides/`; `status` flags edits and unmanaged files; README customization section rewritten |
| The CLI overwrites a user's own same-named agent or skill | high | Rows 11/12: a file without the marker that is not in the lock is a collision; refused with exit 4 and never forceable |
| A restricted YAML parser rejects frontmatter users consider valid YAML, or user frontmatter validates but breaks the agent in the tool | low | Documented subset and frontmatter contract (`name` == stem, no `tools` with `readonly: true`, plain scalars without `: `/` #`); errors name the file, line and the fix ("quote this value"); contract test parses all framework frontmatter |
| Interrupted or failed run leaves a half-applied install | medium | All validation and composition before the first write; atomic renames; lock last; failure exits 1 with "re-run the same command"; rows 3 and 10 make the re-run converge; tested with injected failures |
| Windows: `rename` fails with `EPERM`/`EBUSY` (antivirus, open editors); path separators; CRLF in any input; lost exec bits | medium | Retry with backoff; all lock paths and digest inputs are POSIX, with a cross-OS digest-equality job; every text input CRLF-normalized, content-based text detection, binaries verbatim; `text=auto eol=lf` block; modes not tracked on win32; Windows in the CI matrix; CI step with `shell: bash` |
| Case-insensitive file systems (macOS, Windows) map two composed paths to one file, or a case-only rename deletes the new file | medium | Lowercase unit names (exit 6); case-insensitive duplicate rejection (exit 6); case-only renames paired as one entry and applied as unlink + rename; tested on the macOS and Windows legs |
| Symlinked `.claude`/`.cursor`/skill directories or overrides make the CLI write outside the target or the two tools' adapters alias each other | medium | `lstat` of every managed path, its parents and `overrides/`; any symlink (or symlink-as-file under `core.symlinks=false`) → exit 4 before any write |
| OS and editor junk files (`.DS_Store`, `*.swp`, …) or unmanaged files turn exit 6/3 on for healthy repos and CI | medium | One ignore list applied to overrides, the framework scan and generated directories; narrow "generated directory" definition; unmanaged files informational (exit 0); packaging test keeps self-host scan == `npm pack` set |
| Stale mutex after a crash blocks runs | low | PID + hostname; same-host dead PID reclaimed automatically; message names the holder otherwise; distinct exit 7 so scripts can retry |
| Lock merge conflicts between branches (adjacent sorted records conflict routinely) | medium | Re-rated from low. `install --relock` keeps agreeing and one-sided `override` records, untracks only disagreeing ones and rebuilds `gen` from disk; the unparseable-lock message points to it with `--target`; self-host sentinels remove the version/digest conflict line for framework PRs; a split lock file was considered and rejected (loses the single atomic lock write) |
| A local/unreleased build is mixed with the published build of the same version | medium | Re-rated from low. The digest covers `framework/`, `src/` and `bin/`, identical on every OS; `sync`/`status`/`ack`/`install` refuse on mismatch with a dedicated message (checkout vs packaged variant); a same-version re-pin needs `upgrade --allow-unreleased` and warns; contributors are told to use prerelease versions |
| Self-host detection misfires (a target treated as the source repo or vice versa) | low | `realpathSync.native` equality, case-folded on win32; a devDependency lives under `node_modules/`; a non-self-host CLI refuses on a `framework self` lock or a `soloaifactory` `package.json` with `npm run check` advice; tested |
| The first self-host install in this repo collides with the `sync.sh`-era adapters | low | Restructuring order deletes the legacy adapters in the same commit before the CLI install; the legacy marker is recognized as generated (row 11) as a safety net |
| A bare `npx soloaifactory` writes into a repo that never chose to adopt the tool | low | No command prints usage and exits 2; only an explicit `install` installs; tested without a TTY |
| Detected commands are wrong, and the Verifier then runs or trusts the wrong checks | medium | Placeholder test scripts ignored; ambiguous polyglot repos get placeholders + warning in CI and a prompt interactively; `--primary` and `--set`; detection only prefills; `detect` proposes, never overwrites; the CLI never executes them |
| Unattended installs still produce a Verifier that checks nothing | medium | Install exits 3 and warns; `status` exits 3; Verifier Verdict Rules fail on not-configured Required rows; `factory-build` stops for the human; contract test |
| The Coder "fixes" a not-configured Verifier failure by inventing commands in `config.md` | low | `factory-build` precondition and Step C stop for the human before the Coder sees it; Verifier output says "human action required" |
| TOML detection without a parser misreads `pyproject.toml`/`Cargo.toml` | low | Scanner only looks for table headers and simple keys; fails soft to placeholders; fixtures cover poetry and uv layouts |
| The renderer port changes adapter content compared with `sync.sh` | medium | Golden parity: the pre-change sources snapshot (`golden-sources/`) rendered by the Node renderer must equal the pre-change adapters snapshot (`golden-adapters/`) except the marker line |
| The first npm version lacks provenance, or anyone with tag-push rights can publish | medium | First publish runs from `release.yml` with a short-lived environment-secret token (provenance generated in CI), then trusted publishing pinned to the `npm-publish` environment with required reviewers; workflow-level `contents: read`, `id-token: write` only on `publish`; CHANGELOG check before publish |
| Repository slug changes, breaking `repository.url` (provenance) and README/compare URLs | medium | Decide before the first publish (Open Question 2); one constant in `src/` for URLs; GitHub redirects renamed repos |
| Users without registry access (air-gapped CI) cannot run `status`, or `status --remote` fails behind a proxy or private registry | low | devDependency in Node repos works from `node_modules`; `npx --offline` works from cache; `--prefer-offline` in every printed command; `status --remote` honors `npm_config_registry` and, with `NODE_USE_ENV_PROXY=1`, proxy variables; documented and named in the error |

## Open Questions

Decided (no longer open): Node CLI on npm with zero runtime deps and provenance; JavaScript checked by `tsc`, not compiled TypeScript; minimum Node 24; `sync.sh` folded into `soloaifactory sync` and deleted; framework carried by the package; framework sources at repo-root `framework/` with self-host mode; TSV lock with framework digest; ack-only baselines; exit 6 for invalid overrides; edit protection for generated files; `.frontmatter.yml` (restricted YAML) for `model`/`description`; uninstall keeps `projects/*`/`archive/*` ignore lines while content remains; detection rules for placeholder test scripts and polyglot repos; one exit-code rule for all commands; no auto re-exec; native Windows supported in v1. Revision 3.1 adds: key-span staleness for frontmatter overrides and per-tool `cursor.model`/`claude.model`; one junk-file ignore list, a narrow generated-directory definition and informational unmanaged files; `install --relock` and a single lock file; digest over `framework/`, `src/`, `bin/` with `--allow-unreleased`; self-host sentinels and the restructuring order; bare command prints help; the cross-platform rules; the frontmatter contract; Step C row precedence; the first-publish path, `npm-publish` environment and least-privilege permissions; exit 7 for a held mutex; frozen lock `version` line and exit codes.

Remaining human-only decisions:

1. **npm package name and ownership.** Is the unscoped name `soloaifactory` available, and who owns the npm account (with 2FA) that registers the trusted publisher? If it is taken, choose a scoped name (e.g. `@<owner>/soloaifactory`), which changes every `npx` command and the `bin` usage text. (How the first version is published is decided: from `release.yml` with a one-time environment-secret token; see Versioning and release.)
2. **Canonical repository slug.** Will the GitHub repo be renamed from `sdlc-orchestration-framework` (e.g. to `soloaifactory`) before the first publish? `package.json` `repository.url` must match the publishing repo for provenance, and README and status/upgrade URLs depend on it.
3. **First version.** Is the first published version `0.1.0`?
4. **License.** The repository has no `LICENSE` file, and the npm package needs a `license` field and a `LICENSE` file (both in the File Impact Map). Which license?

## Approval

- [ ] Human has reviewed and approved this Design Doc

<!-- Human: add comments or request revisions below -->

## Revision history

**Revision 2 (2026-11-18), in response to `evaluations/00-design-evaluation.md` (verdict: needs-revision) and human direction.**

Human direction applied: (a) user scope removed from v1 and moved to Non-Goals, with the lock's `scope` record and "ignore unknown record kinds" rule keeping it addable later; (b) in-place customization replaced by an overrides layer; (c) branch/SHA installs and the .NET detector trimmed (both additive later: `source ref` record, one more `detect_*` function) because nothing validates them and they widened the test matrix.

| Evaluator item | Resolution | Where |
|---|---|---|
| Revision 1 / finding 1 (pin undone by `--version` default) | `install` defaults to the running script's version and refuses to change an existing install's version; `upgrade` defaults to latest; Goal 10 and risk table reworded | Sources and versions; Goals 10; Flags |
| Revision 2 / finding 2 (conflict state not durable) | **Moot by design**: no conflict state exists. Modified pristine files block the run with nothing written. The remaining "pending" signal, stale overrides, lives in the committed lock and is reported by `status` on every clone until `ack` | Overrides layer decision; Override baselines and drift; Goal 4 |
| Revision 3 / finding 3 (mutex across re-exec) | Bootstrap only fetches, verifies and `exec`s; staged process owns target, PID mutex and cleanup; dry-run/status/detect never write, including directories | Process model; Goal 6 |
| Revision 4 / finding 4 (source-checkout heuristic) | Heuristic removed; local source only with explicit `--source`; positive `.factory-source` marker guards the source repo; interrupted installs adopt | Sources and versions; Process model; Data Model §9 |
| Revision 5 / finding 7 (idempotency vs timestamp) | `installed` field removed; lock and git blocks rewritten only when content changes; tree hash defined to include dirs and modes | Data Model §1; Process model; Testing |
| Revision 6 / finding 11 (lock merge recovery) | Unparseable-lock definition; "delete lock and re-run `install`" is the only recovery; adopt blocks differing files; "re-hashes" wording removed | Lock failure and recovery |
| Revision 7 (OQ 2 and 4; `sync.sh --remove`) | Decided: overrides layer with generated templates; `sync.sh` gains `--remove` (and collision refusal), so `factory.sh` never replicates the marker scan | Customization decision; `sync.sh` changes; File Impact Map |
| Revision 8 / finding 10 (uninstall blast radius, order) | Global half **moot** (no user scope). Order defined (`sync.sh --remove`, payload, blocks, lock, dirs); consequence for kept overrides stated | Uninstall |
| Revision 9 / finding 8 (no merge base) | **Moot by design**: no file-level conflicts. The upgrade commit's diff of committed `framework/` is the base-to-new upstream change; `status` prints a `git log -p` hint for stale overrides | Customization decision; Override baselines |
| Revision 10 / finding 6 (renderer corruption) | `ENVIRON` value passing, `index`/`substr` construction, no user data in `sub`/`gsub`; tests with `&&`, `&`, `\`, `\|`, `$(…)` | Config onboarding; Testing |
| Revision 11 / finding 12 (CRLF, file mode) | Managed `.gitattributes` block; explicit `chmod 755`; `mode` action and `status` check | Data Model §3; decision table |
| Revision 12 / finding 13 (Verifier gap) | Non-Goal narrowed; Verifier keyed on template labels, unfilled Required → `fail`; `factory-build` precondition tightened; contract test; Goal 1 criterion adds `node-no-lint` | Verifier alignment; Goals 1, 9; File Impact Map |
| Revision 13 / finding 5 (checksum overstated) | SHA-256 reclassified as integrity only; authenticity out of scope for v1; immutable releases + tag protection required before the first tag | Risks; Versioning and release; Open Question 3 |
| Revision 14 / finding 9 (user-scope version skew) | **Moot**: user scope removed from v1 | Non-Goals |
| Hard Questions 1–5 | 1: own version / only `upgrade` changes versions. 2: no conflict state; stale overrides in the lock. 3: `sync.sh` changes accepted; decision table reduced to "blocked or proceed". 4: staged process owns mutex and staging dir; read-only commands take no mutex. 5: user scope, ref installs, `uninstall --scope user` and .NET cut from v1 without affecting lock format 1 | Throughout |
| Trade-off notes (offline re-runs, prompt friction) | Offline `install`/`upgrade` accepted as a Non-Goal; per-value prompts replaced by one accept/edit/skip prompt | Non-Goals; Config onboarding |

**Revision 3 (2026-11-18), in response to the revision-2 evaluation in `evaluations/00-design-evaluation.md` (verdict: needs-revision) and human decisions.**

Human direction applied: (A) the CLI is rewritten as a zero-runtime-dependency Node program on npm with provenance, invoked as `npx soloaifactory@<version>`; `sync.sh` is folded into `soloaifactory sync` and deleted; the npm package carries the framework, so targets keep only overrides, `config.md`, generated adapters/templates/scaffolding, managed git blocks and the lock, and the locked package version defines "pristine". (B) The Evaluator's language-independent findings are answered as directed: ack-only baselines, a distinct exit code for invalid overrides, edit protection for generated files, Verifier Verdict Rules and Step C routing, frontmatter overrides, uninstall keeping ignore lines, stricter detection, and the lower-severity items. Native Windows moves from Non-Goal to supported. Project scope only and the overrides layer are kept.

| Evaluator item | Resolution | Where |
|---|---|---|
| Required revision 1 / N1 (baselines inferred at record time) | **Resolved.** Only `ack <path>` writes `override` records; `install`/`upgrade`/`sync` never record or infer them. Untracked, stale and orphaned overrides are attention items (exit 3). Goal 4 tests cover "acked on v1, upgrade merged first, then rebase", the never-acked variant, a standalone override whose name upstream adds, and a renamed base. Deleting the lock makes all overrides untracked instead of resetting them to current | Override baselines and drift; Goal 4; Testing |
| Required revision 2 / N2 (frozen bootstrap hand-off) | **Moot because** there is no bootstrap: each `npx soloaifactory@<v>` runs that version's own code end to end, with no old script fetching or `exec`ing a new one. The only cross-version contracts are the lock `format` and the overrides layout, both versioned and named as such. The version-mismatch messages point at the exact `npx soloaifactory@<v>` command | Versions and pinning; Process model; Versioning and release |
| Required revision 3 / N3 (`sync.sh` exit 1 overloaded; post-apply failure unspecified) | **Resolved.** Invalid overrides layout is exit 6, detected in pre-flight by every composing command before any write. Composition happens in memory before the first write, so a layout error can no longer surface after writes. Any failure during APPLY exits 1, does not write the lock and prints "re-run the same command to finish"; tests inject the failure and check the re-run | Overrides composition; Process model; Exit codes; Testing |
| Required revision 4 / N4 (`--source` used the bootstrap's allowlist) | **Moot because** `--source` and `PAYLOAD_PATHS` are gone: the CLI always reads the framework from its own package root. Local/unreleased builds are detected through the lock's framework digest | Versions and pinning; Removed with the bash model |
| Required revision 5 / N5 (`--staged DIR` trusted and `rm -rf`'d) | **Moot because** there is no staging directory, no `--staged` flag and no temp directory; the CLI writes only inside the target (temp files sit next to their destination and are its own) | Process model; Removed with the bash model |
| Required revision 6 / N6 (locale-dependent sorting) | **Resolved differently.** All ordering uses one comparator on JavaScript strings (UTF-16 code units, locale-independent); managed paths are validated to ASCII, where this equals byte order; `localeCompare`/`Intl.Collator` are banned by lint; a test checks identical lock bytes under `en_US.UTF-8` and `C` | Process model (Deterministic ordering); Data Model §1; Testing |
| Required revision 7 / N7 (silent loss of template edits; `--dest` ambiguity) | **Resolved.** The lock hashes every generated file; edits to `.ai-factory/templates/` and to marker-carrying adapters block `install`/`upgrade`/`sync` (exit 4, "move into `overrides/`"), and `--force` backs up first. Templates are always written under the target repo root; `--dest` no longer exists. Unmanaged files in generated directories are never deleted | Generated-file decision table; Overrides composition; What lives where; Goal 3 |
| Required revision 8 / N8 (Verifier Verdict Rules and Step C) | **Resolved.** File Impact Map rewrites `factory-verifier.md`'s Verdict Rules ("fail if any check exits non-zero or any Required row is not configured") and its "Important" skipped bullet, and adds a `factory-build` Step C row ("not configured → stop and ask the human; do not route to the Coder"). The contract test covers both | Verifier alignment; File Impact Map; Testing |
| Required revision 9 / N9 (granularity; orphaned replacements) | **Resolved.** `overrides/agents/<name>.frontmatter.yml` (restricted YAML subset, own zero-dep parser) changes `model` and `description`. Replacements whose base was dropped or renamed are orphaned attention items until acked; orphaned appends/frontmatter stay attention until deleted. Coarse-append risk re-rated to medium | Overrides composition; Override baselines and drift; Data Model §5; Risks |
| Required revision 10 / N10 (uninstall exposes `projects/`/`archive/`) | **Resolved.** Uninstall rewrites the `.gitignore` block to keep the four `projects/*`/`archive/*` lines while either directory has content, and warns with a listing | Uninstall; Data Model §2; Goal 5 |
| Required revision 10 / N11 (release mechanics vs immutable releases and tag protection) | **Moot because** GitHub release assets, immutable releases and tag protection are no longer part of distribution. `release.yml` publishes to npm only after the full test matrix passes; a failed run publishes nothing and the tag can be re-pushed; npm forbids republishing a version | Versioning and release |
| Required revision 10 / N12 (detection fills Test wrongly) | **Resolved.** The `npm init` placeholder test script is treated as absent; the polyglot primary is the ecosystem with a real test signal; with several signals, non-interactive mode leaves Commands as placeholders and warns; new `--primary` flag | Config onboarding; Goal 1 (c), (d) |
| Lower: lock writer drops unknown record kinds | **Resolved.** Unknown kinds preserved verbatim on every rewrite | Lock failure and recovery; Data Model §1 |
| Lower: inconsistent exit codes (`install` 3 for stale vs 0 for unfilled Test/Lint) | **Resolved.** One rule: any completed command exits 3 iff the post-run `status` has an attention item | Config onboarding; Exit codes |
| Lower: does `ack` take the mutex; `ack` on unknown or untracked paths | **Resolved.** `ack` takes the mutex; unknown or non-override paths → exit 2, nothing written; untracked overrides are exactly what `ack` records; already-current → no-op; orphaned append/frontmatter → exit 2 | Commands (`ack` details); Process model |
| Lower: downgrade without `--version` | **Resolved.** There is no `--version` payload flag; a downgrade (older CLI than lock) exits 4 with downgrade wording unless `--allow-downgrade` | Versions and pinning; Flags |
| Lower: `--dry-run` prompts for config | **Resolved.** `--dry-run` never prompts and shows the detected values in the plan | Process model; Goal 6 |
| Lower: forced `text eol=lf` on all of `framework/**` / `overrides/**` | **Resolved.** `.gitattributes` block scoped to `*.md`, `*.yml` and the lock; correctness no longer depends on it because hashing normalizes CRLF | Data Model §3 |
| Lower: no CI snippet for target repos | **Resolved.** One-line `npx --yes "soloaifactory@$(awk …)" status` step, documented in README | Invocation forms |
| Prior-status note: refusal message should say "downgrade" | **Resolved** (version table messages) | Versions and pinning |
| Prior-status note: duplicate lock records not "unparseable" | **Resolved.** Duplicate `gen`/`override` paths make the lock unparseable | Lock failure and recovery |
| Revision-2 OQ 3 / checksum gives no authenticity | **Resolved by the channel.** npm sha512 integrity, immutable versions and Sigstore provenance through trusted publishing replace the same-release SHA-256; runtime enforcement of provenance stays a Non-Goal | Runtime choice; Versioning and release; Risks |
| Hard Questions 1–5 | 1: only `ack` records; untracked = exit 3. 2: nothing is frozen except the lock format and overrides layout; there is no bootstrap. 3: invalid overrides = exit 6 in pre-flight; post-apply failure = exit 1, lock not written, re-run. 4: edits to templates and adapters block like other protected files. 5: yes, `model:` through `.frontmatter.yml` | Throughout |

**Removed because they existed only for the bash + `curl | bash` model:** bootstrap phase and staged re-exec; `--staged`, `--source`, `--repo`, payload `--version`; `$TMPDIR` staging and traps; release tarball, `.sha256` and `pack`; tag-pinned raw URLs and GitHub-redirect `latest` resolution; `FACTORY_REPO`, `FACTORY_DOWNLOAD_BASE`, `FACTORY_SH_LIB`; immutable-release and tag-protection preconditions; `PAYLOAD_PATHS`, the payload decision table and the "local edit to `framework/` blocks" rule (no framework in targets); `chmod`/`mode` handling; `LC_ALL=C` locale rules; the awk renderer and its escaping rules; `jq`/awk JSON scanning; the `.factory-source` marker; the bash test harness, shellcheck and the bash 3.2 macOS job; `sync.sh` itself and its `--dest`/`--remove` flags.

**Revision 3.1 (2026-11-18), a targeted revision in response to the revision-3 evaluation in `evaluations/00-design-evaluation.md` (verdict: needs-revision, "short and targeted") and human decisions.**

Human direction applied: the revision-3 architecture is unchanged; native Windows support stays in v1, with every Windows part of F7 addressed; the answers given for F1–F10 and the lower-severity items are applied as specified. Project scope, the overrides layer, ack-only baselines and everything else revision 3 settled are kept.

| Evaluator item | Resolution | Where |
|---|---|---|
| F1 / RR1 (junk files; undefined "generated directory") | One junk-file ignore list (`.DS_Store`, `Thumbs.db`, `desktop.ini`, `*~`, `*.swp`, `*.swo`, `.#*`, `*.orig`, `*.rej`), applied to `overrides/`, the framework scan (packaged and self-host) and generated directories; packaging test asserts the self-host scan equals the `npm pack` `framework/` set and a contract test that no framework file matches the list. Generated directories are exactly `.ai-factory/templates/` and each generated `.<tool>/skills/<name>/`. Unmanaged files and leftovers are informational (exit 0) | What lives where; Status; Exit codes; Testing |
| F2 / RR2 (lock conflicts; destructive recovery) | `install --relock`: two-sided lenient parse (diff3 base discarded; hand-merged duplicates count as sides); `override` records kept when sides agree or only one has them, untracked when they disagree; `gen` rebuilt by the decision table (disk == exp adopted; dropped paths removed only when matching a side's hash). Unparseable-lock message points to `--relock` with `--target`. Risk re-rated to medium. Separate overrides lock considered and rejected (two files cannot be replaced atomically) | Lock failure and recovery; Flags; Risks; Goal 4 (vi) |
| F3 / RR3 (whole-file staleness; per-tool model) | A `.frontmatter.yml`'s base digest covers only the line spans of the keys it overrides; appends keep the whole base file, stated as a conservative choice. `cursor.model` / `claude.model` alongside `model`; precedence `<tool>.model` > `model` > base; dotted keys only in that form, never emitted; also accepted in replacement and new agents | Overrides composition; Override baselines and drift; Data Model §5; Goal 4 (v) |
| F4 / RR4 (digest scope, OS dependence, looping advice) | Digest over `framework/**`, `src/**`, `bin/**`, POSIX relative paths, text LF-normalized, binary raw; committed fixture digest plus a `digest-equal` CI job across all legs. Dedicated same-version digest message (checkout vs packaged variant) that never echoes the user's command; same-version re-pin by `upgrade` needs `--allow-unreleased` and warns; `install` refuses with the same message | Versions and pinning; Data Model §9; Flags; Testing |
| F5 / RR5 (self-host first install, lock churn, advice) | Binding restructuring order (capture golden adapters and pre-change sources → move sources → delete legacy adapters, `sync.sh` and `.ai-factory/framework/` in the same commit → CLI install). Legacy marker `Generated by .ai-factory/sync.sh` counts as generated (row 11). Self-host lock records `version 0.0.0-self` and `framework self`. A non-self-host CLI on that lock or a `soloaifactory` `package.json` refuses with `npm run check` / `npm run sync` advice. Golden parity renders `golden-sources/`, not the modified framework | Repository restructuring; Versions and pinning; Decision table; Testing; File Impact Map |
| F6 / RR6 (bare command installs) | No command prints usage on stderr and exits 2; only an explicit `install` installs | Process model; Commands; Invocation forms |
| F7 / RR7 (cross-platform) | New "Cross-platform rules": lowercase unit names and case-insensitive duplicate rejection (exit 6), case-only renames paired; `lstat` symlink policy for managed paths, parents and overrides, incl. symlink-as-file under `core.symlinks=false` (exit 4); CRLF→LF for every input; content-based text detection (valid UTF-8, no NUL) instead of an extension list, binaries never normalized (resolves the "LF-normalize everything" contradiction); `.gitattributes` uses `text=auto eol=lf`; exec bits written as `0o755` when the source has any, asserted in packaging, not tracked on win32 and never hashed; CI step with `shell: bash` and a CRLF-safe `node -p` version read; review hint without process substitution; `realpathSync.native` with win32 case-folding | Cross-platform rules; Data Model §3; Invocation forms; Override baselines and drift; Testing |
| F8 / RR8 (frontmatter contract; lax plain scalars) | Contract for framework, replacement and new agents and skills: `name` == stem (exit 6), `description` required, known keys, unknown keys passed through, `tools` with `readonly: true` is exit 6, all parsed by the subset reader. Plain scalars reject `: ` and ` #` ("quote this value"). Contract test parses all framework frontmatter | Overrides composition; Data Model §5; Testing |
| F9 / RR9 (Step C row shadowed) | The not-configured row is first after `pass \| pass`, a sentence states it overrides every other row, and the contract test asserts its position | Verifier alignment; File Impact Map |
| F10 / RR10 (first publish, unguarded publishing) | First publish from `release.yml` with a short-lived environment-secret token (provenance from CI OIDC), then trusted publishing; `environment: npm-publish` with required reviewers, pinned in the trusted-publisher config; workflow-level `permissions: contents: read`, `id-token: write` only on `publish`; CHANGELOG-section check in `check`. OQ1 no longer mentions a manual publish | Versioning and release; File Impact Map; Risks; Open Questions |
| Lower: `.factory-backup/` ignore line dropped by uninstall | Reduced block keeps that line while the directory exists | Uninstall; Data Model §2 |
| Lower: managed git block edits silently replaced | Stated as the one exception to Goal 3, with a visible plan line | Goal 3; Managed git blocks |
| Lower: undeclared frozen contracts | Lock `version` record shape and exit-code meanings 0–7 declared frozen; changing them is a major version | Versioning and release; Data Model §1; Exit codes |
| Lower: npx network claims; `--yes` | Accurate caching language (revalidation, GC); `--yes --prefer-offline` in every printed pinned command and the CI step (`@latest` lines omit `--prefer-offline` so they resolve fresh) | Versions and pinning; Invocation forms |
| Lower: exit 4 conflates transient and permanent refusals | New exit 7 for a held mutex (transient, retryable) | Process model; Exit codes |
| Lower: `node --test` default patterns | `node --test "test/**/*.test.js"` | Testing; Data Model §8; File Impact Map |
| Lower: File Impact Map omissions | Added `examples/oauth2/evaluations/00-design-evaluation.md` path fix, `LICENSE`, `golden-sources/` and digest fixtures, `src/fs-policy.js`, `relock`/`fs-policy`/`digest` tests | File Impact Map |
| Lower: `show <path>` by path joining | Resolved only against the packaged file list; anything else exit 2 | Commands; Exit codes |
| Lower: devDependency check semantics | `status` compares the declared spec in `package.json`, never `node_modules`; ranges are attention items | Versions and pinning; Status |
| Lower: lock deletion loses `targets` | Recovery message includes `--target`; `--relock` unions the sides' targets unless `--target` is given | Lock failure and recovery |
| Lower: `status --remote` proxy and registry | Honors `npm_config_registry`; `.npmrc` not read; proxy variables need `NODE_USE_ENV_PROXY=1`; documented and named in the error | Process model; Environment variables |
| Lower: unknown lock kinds across `--allow-downgrade` | Preserved; the consequence is stated and accepted | Lock failure and recovery |
| Lower: "sorted after known kinds" vs "in place after rewrite" | One rule: after the known kinds, sorted by full line; tests check that | Lock failure and recovery; Data Model §1; Testing |
| Hard Question 1 (frontmatter base; per-tool model) | Only the overridden keys' line spans; `cursor.model` / `claude.model` in the same `.frontmatter.yml` | Override baselines and drift; Data Model §5 |
| Hard Question 2 (generated directories; ignored names) | `.ai-factory/templates/` and each generated `.<tool>/skills/<name>/`; the nine-pattern junk list everywhere; unmanaged files exit 0 | What lives where |
| Hard Question 3 (non-destructive lock repair) | Yes: `install --relock` | Lock failure and recovery |
| Hard Question 4 (legacy adapters; self-host lock line) | Deleted in the restructuring commit, and the legacy marker is recognized as a safety net; self-host lock records `version 0.0.0-self` / `framework self` | Repository restructuring; Versions and pinning |
| Hard Question 5 (digest scope; mismatch message) | `framework/`, `src/`, `bin/`; a dedicated message that names both digests and the actual remedy (published CLI, or `upgrade --allow-unreleased`) | Versions and pinning; Data Model §9 |
