#!/usr/bin/env bash
# Scaffold for the node-npm-init eval case: a Node project whose only test
# script is the placeholder `npm init` writes. Runs in the empty eval
# workspace and writes nothing outside it.
set -euo pipefail

commit() {
  GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" \
    git -c user.name="soloAIfactory evals" -c user.email="evals@example.invalid" \
    -c commit.gpgsign=false commit -q -m "$1"
}

git -c init.defaultBranch=main init -q

cat >package.json <<'EOF'
{
  "name": "demo",
  "version": "1.0.0",
  "description": "",
  "main": "index.js",
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "author": "",
  "license": "ISC"
}
EOF

cat >index.js <<'EOF'
module.exports = function greet(name) {
  return `Hello, ${name}!`;
};
EOF

git add -A
commit "Initial commit"
