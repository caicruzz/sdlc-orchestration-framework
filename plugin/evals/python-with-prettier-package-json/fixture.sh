#!/usr/bin/env bash
# Scaffold for the python-with-prettier-package-json eval case: a Python
# project (pytest and ruff configured) plus a tooling-only package.json that
# just pins Prettier. Runs in the empty eval workspace and writes nothing
# outside it.
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
dev = ["pytest>=8", "ruff>=0.6"]

[tool.pytest.ini_options]
testpaths = ["tests"]

[tool.ruff]
line-length = 100
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

cat >package.json <<'EOF'
{
  "name": "demo-tooling",
  "private": true,
  "devDependencies": {
    "prettier": "^3.3.0"
  }
}
EOF

cat >.prettierrc <<'EOF'
{
  "proseWrap": "always"
}
EOF

git add -A
commit "Initial commit"
