#!/usr/bin/env bash
# Scaffold for the empty-repo eval case: a git repository with no marker files
# and no commits. Runs in the empty eval workspace and writes nothing outside
# it.
set -euo pipefail

git -c init.defaultBranch=main init -q
