#!/usr/bin/env bash
# Runs every test script in the repository.
#
# Order: scripts/check.sh first (when it exists), then every scripts/test-*.sh
# in name order. Each script runs with the same bash that runs this file
# ("$BASH"), from the repository root. One failing script never stops the
# others; the run exits 0 only if every script exited 0.
#
# Only check.sh and test-*.sh are picked up: paid or slow runners such as
# scripts/run-evals.sh are never run from here.
set -euo pipefail
cd "$(dirname "$0")/.."

# Collect test scripts in byte (C locale) name order without changing the
# locale of the scripts we run.
test_list=$(
  LC_ALL=C
  for f in scripts/test-*.sh; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
  true
)

if [ -z "$test_list" ]; then
  echo "no test scripts found"
  exit 1
fi

scripts=()
if [ -f scripts/check.sh ]; then
  scripts+=("scripts/check.sh")
fi
while IFS= read -r f; do
  scripts+=("$f")
done <<EOF
$test_list
EOF

passed=0
total=0
for script in "${scripts[@]}"; do
  total=$((total + 1))
  if "$BASH" "$script" </dev/null; then
    passed=$((passed + 1))
    echo "PASS $script"
  else
    rc=$?
    echo "FAIL $script (exit $rc)"
  fi
done

echo "$passed/$total test scripts passed"
[ "$passed" -eq "$total" ]
