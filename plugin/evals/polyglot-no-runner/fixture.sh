#!/usr/bin/env bash
# Scaffold for the polyglot-no-runner eval case: Python and Go side by side,
# both with test signals, and no task runner (no Makefile, justfile, Taskfile,
# tox or nox). Runs in the empty eval workspace and writes nothing outside it.
set -euo pipefail

commit() {
  GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" \
    git -c user.name="soloAIfactory evals" -c user.email="evals@example.invalid" \
    -c commit.gpgsign=false commit -q -m "$1"
}

git -c init.defaultBranch=main init -q

cat >pyproject.toml <<'EOF'
[project]
name = "demo"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = []

[project.optional-dependencies]
dev = ["pytest>=8"]

[tool.pytest.ini_options]
testpaths = ["tests"]
EOF

mkdir -p tests
cat >tests/test_x.py <<'EOF'
def test_truth():
    assert 1 + 1 == 2
EOF

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

git add -A
commit "Initial commit"
