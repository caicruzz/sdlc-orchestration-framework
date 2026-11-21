# soloAIfactory Project Configuration

Edit this file to match your project's tech stack and conventions.
The Architect, Planner, Coder, Reviewer, and Verifier agents all read this file.

## Tech Stack

- **Language**: <!-- e.g. TypeScript, Python, Go, Rust, C# -->
- **Runtime**: <!-- e.g. Node.js 22, Python 3.12, Go 1.22 -->
- **Framework**: <!-- e.g. Next.js, FastAPI, Express, Django, ASP.NET -->
- **Package Manager**: <!-- e.g. npm, pnpm, poetry, cargo, dotnet -->

## Project Structure

- **Source directory**: <!-- e.g. src/ -->
- **Test directory**: <!-- e.g. tests/ or src/__tests__/ -->
- **Entry point**: <!-- e.g. src/index.ts -->
- **Config files**: <!-- e.g. tsconfig.json, .eslintrc.js, pyproject.toml -->

## Commands

| Check | Command | Notes |
|---|---|---|
| **Install** | <!-- e.g. npm install --> | |
| **Test** | <!-- e.g. npm test --> | Required |
| **Lint** | <!-- e.g. npm run lint --> | Required |
| **Type check** | <!-- e.g. npx tsc --noEmit --> | Optional — remove if not applicable |
| **Build** | <!-- e.g. npm run build --> | Optional — remove if not applicable |
| **Format** | <!-- e.g. npx prettier --check . --> | Optional |

## Build

Settings for the `factory-build` skill. Delete a row to use its default.

| Setting | Value | Notes |
|---|---|---|
| **max_concurrent_tasks** | 3 | Most tasks running at once, each in its own git worktree. `1` runs one at a time |
| **max_iterations** | 3 | Most Coder passes per task before it is set `blocked` and escalated to you |
| **worktree_dir** | ../<repo>-worktrees | Where task worktrees go, relative to the repo root. Keep it outside the repo |
| **base_branch** | <!-- e.g. main; leave empty to use the branch checked out when the build starts --> | The epic branch `factory/<slug>` starts here, and the final PR targets it |
| **handoff_after_rounds** | 6 | Review + Verify rounds (across all tasks) one orchestrator session runs before it saves `build-state.md` and asks you to start a fresh one. `0` turns it off |
| **handoff_at_percent** | 70 | Context usage at which the factory hooks or plugin ask the orchestrator to hand off. Only used when they are installed |

## Conventions

- **Code style**: <!-- e.g. Prettier, Black, rustfmt -->
- **Naming**: <!-- e.g. camelCase for functions/files, PascalCase for classes -->
- **Commit style**: <!-- e.g. Conventional Commits (feat:, fix:, etc.) -->
- **Test naming**: <!-- e.g. describe/it blocks, test() functions -->
- **Import style**: <!-- e.g. absolute imports from src/, relative within module -->

## Architecture Notes

<!-- Add any project-specific rules that agents should know about -->
<!-- Examples: -->
<!-- - All API routes must validate input with Zod schemas -->
<!-- - Database access only through repository classes in src/repositories/ -->
<!-- - State management uses Zustand — do not add Redux or Context -->
<!-- - Error handling uses Result<T, E> pattern, not exceptions -->
