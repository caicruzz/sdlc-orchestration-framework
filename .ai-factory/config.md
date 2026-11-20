# soloAIfactory Project Configuration

Edit this file to match your project's tech stack and conventions.
The Architect, Planner, Coder, Reviewer, and Verifier agents all read this file.

## Tech Stack

- **Language**: Markdown, Bash
- **Runtime**: bash 3.2+ (macOS `/bin/bash`)
- **Framework**: Claude Code and Cursor skills and subagents
- **Package Manager**: none

## Project Structure

- **Source directory**: `plugin/` (from a later task on; `.ai-factory/framework/` until then)
- **Test directory**: `scripts/test-*.sh`
- **Entry point**: <!-- e.g. src/index.ts -->
- **Config files**: <!-- e.g. tsconfig.json, .eslintrc.js, pyproject.toml -->

## Commands

| Check | Command | Notes |
|---|---|---|
| **Install** | `brew install shellcheck` (macOS) or `apt-get install shellcheck` | |
| **Test** | `/bin/bash scripts/test.sh` | Required |
| **Lint** | `/bin/bash scripts/lint.sh` | Required |
| **Type check** | `none` | Optional — remove if not applicable |
| **Build** | `none` | Optional — remove if not applicable |
| **Format** | <!-- e.g. npx prettier --check . --> | Optional |

## Conventions

- **Code style**: <!-- e.g. Prettier, Black, rustfmt -->
- **Naming**: <!-- e.g. camelCase for functions/files, PascalCase for classes -->
- **Commit style**: Conventional Commits
- **Test naming**: one `scripts/test-<area>.sh` per area, one function per scenario
- **Import style**: <!-- e.g. absolute imports from src/, relative within module -->

## Architecture Notes

- Every task adds or extends a `scripts/test-*.sh` file for its scenarios; `scripts/test.sh` runs them all. Tests assert lasting results, never a diff or a commit. A task that intentionally changes something an earlier test asserts updates that test in the same change. Tests never touch the real `$HOME` or make paid model calls.
