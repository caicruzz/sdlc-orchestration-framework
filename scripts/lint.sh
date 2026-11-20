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

files=()
while IFS= read -r -d '' f; do
  # A tracked file deleted from the working tree is still listed; skip it.
  [ -f "$f" ] && files+=("$f")
done < <(git ls-files -co --exclude-standard -z -- '*.sh')

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
