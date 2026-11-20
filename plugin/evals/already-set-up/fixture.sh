#!/usr/bin/env bash
# Scaffold for the already-set-up eval case: a Go module that is already set
# up (Test and Lint filled, both .gitkeep files present). Conventions,
# Install, Format and Architecture Notes are unfilled and .gitignore has none
# of the four factory lines; none of that is a gap. Runs in the empty eval
# workspace and writes nothing outside it.
#
# The graders hold anchored full-content regexes of config.md and .gitignore
# exactly as written here; keep them in sync when changing either file.
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

cat >.gitignore <<'EOF'
bin/
*.log
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
- **Runtime**: Go 1.22
- **Framework**: none
- **Package Manager**: go modules

## Project Structure

- **Source directory**: .
- **Test directory**: .
- **Entry point**: <!-- e.g. src/index.ts -->
- **Config files**: go.mod

## Commands

| Check | Command | Notes |
|---|---|---|
| **Install** | <!-- e.g. npm install --> | |
| **Test** | `go test ./...` | Required |
| **Lint** | `go vet ./...` | Required |
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
