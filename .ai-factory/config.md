# SDLC Project Configuration

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
