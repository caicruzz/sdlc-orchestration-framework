#!/usr/bin/env bash
# Scaffold for the go-plain eval case: a Go module with one _test.go file and
# no golangci-lint config. Runs in the empty eval workspace and writes nothing
# outside it.
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

git add -A
commit "Initial commit"
