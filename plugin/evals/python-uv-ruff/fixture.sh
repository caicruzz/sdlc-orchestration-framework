#!/usr/bin/env bash
# Scaffold for the python-uv-ruff eval case: a uv-managed Python project with
# pytest and ruff configured in pyproject.toml, a uv.lock and one test. Runs
# in the empty eval workspace and writes nothing outside it.
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

[dependency-groups]
dev = ["pytest>=8", "ruff>=0.6"]

[tool.pytest.ini_options]
testpaths = ["tests"]

[tool.ruff]
line-length = 100
EOF

cat >uv.lock <<'EOF'
version = 1
requires-python = ">=3.12"

[[package]]
name = "demo"
version = "0.1.0"
source = { editable = "." }
EOF

mkdir -p src/demo tests
cat >src/demo/__init__.py <<'EOF'
def add(a: int, b: int) -> int:
    return a + b
EOF

cat >tests/test_x.py <<'EOF'
from demo import add


def test_add():
    assert add(1, 2) == 3
EOF

git add -A
commit "Initial commit"
