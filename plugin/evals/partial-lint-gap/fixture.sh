#!/usr/bin/env bash
# Scaffold for the partial-lint-gap eval case: a Go module whose config.md has
# Test filled and Lint unfilled (both .gitkeep files present), so Lint is the
# only gap. Runs in the empty eval workspace and writes nothing outside it.
#
# The config grader holds an anchored full-content regex of config.md as
# written here (with only the Lint row free); keep them in sync.
set -euo pipefail

commit() {
  GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" \
    git -c user.name="soloAIfactory evals" -c user.email="evals@example.invalid" \
    -c commit.gpgsign=false commit -q -m "$1"
}

git -c init.defaultBranch=main init -q

cat >go.mod <<'EOF'
module example.com/demo

go 1.22
EOF

cat >add.go <<'EOF'
package demo

// Add returns the sum of a and b.
func Add(a, b int) int {
	return a + b
}
EOF

cat >add_test.go <<'EOF'
package demo

import "testing"

func TestAdd(t *testing.T) {
	if got := Add(1, 2); got != 3 {
		t.Fatalf("Add(1, 2) = %d, want 3", got)
	}
}
EOF

mkdir -p .ai-factory/projects .ai-factory/archive
: >.ai-factory/projects/.gitkeep
: >.ai-factory/archive/.gitkeep

cat >.ai-factory/config.md <<'EOF'
# soloAIfactory Project Configuration

Edit this file to match your project's tech stack and conventions.
The Architect, Planner, Coder, Reviewer, and Verifier agents all read this file.

## Tech Stack

- **Language**: Go
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
| **Test** | `go test ./...` | Required |
| **Lint** | <!-- e.g. npm run lint --> | Required |
| **Type check** | none | Optional — remove if not applicable |
| **Build** | `go build ./...` | Optional — remove if not applicable |
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
EOF

git add -A
commit "Initial commit"
