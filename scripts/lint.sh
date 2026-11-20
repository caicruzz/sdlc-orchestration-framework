#!/usr/bin/env bash
# Lints every shell script in the repository.
#
# Covers every *.sh file that is tracked or untracked-but-not-ignored, so new
# scripts are linted before they are committed. Each file gets `bash -n`
# (syntax) and then `shellcheck`. Exits 0 only if both pass for every file.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck is not installed (macOS: brew install shellcheck; Debian/Ubuntu: apt-get install shellcheck)" >&2
  exit 1
fi

# The file list comes from git, so outside a work tree there is nothing to
# trust: fail loudly instead of reporting "no shell scripts to lint".
if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null || true)" != "true" ]; then
  echo "lint.sh must run inside a git work tree: $(pwd -P) is not one" >&2
  exit 1
fi
# NUL-delimited (-z) so git never C-quotes a name (quotes, backslashes, tabs,
# control characters) and every listed file is linted. The list goes to a temp
# file so git's exit status is checked here (a failure inside process
# substitution would be invisible to set -e). Bare assignment: a mktemp
# failure stops the run; the trap is installed only for a real file.
list_file=$(mktemp "${TMPDIR:-/tmp}/lint.XXXXXX")
if [ -z "$list_file" ] || [ ! -f "$list_file" ]; then
  echo "mktemp did not create a file list; cannot lint" >&2
  exit 1
fi
trap 'rm -f "$list_file"' EXIT
if ! git ls-files -co --exclude-standard -z -- '*.sh' >"$list_file"; then
  echo "git ls-files failed; cannot list shell scripts to lint" >&2
  exit 1
fi

files=()
while IFS= read -r -d '' f; do
  # A tracked file deleted from the working tree is still listed; skip it.
  if [ -n "$f" ] && [ -f "$f" ]; then files+=("$f"); fi
done <"$list_file"

if [ "${#files[@]}" -eq 0 ]; then
  echo "no shell scripts to lint"
  exit 0
fi

failed=0
for f in "${files[@]}"; do
  if ! "$BASH" -n "$f"; then
    echo "FAIL bash -n $f"
    failed=1
  fi
  if ! shellcheck "$f"; then
    echo "FAIL shellcheck $f"
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "lint failed"
  exit 1
fi
echo "lint passed (${#files[@]} files)"
