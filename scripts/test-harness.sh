#!/usr/bin/env bash
# T000 self-test for the test and lint runners and this repo's config.
#
# Runner scenarios run in fresh git repositories under ${TMPDIR:-/tmp} that
# hold copies of scripts/test.sh and scripts/lint.sh only (never this file, so
# nothing recurses). The real repository is never modified and the temporary
# directory is removed on exit.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_ROOT=$(pwd -P)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-harness.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

CONFIG=".ai-factory/config.md"
TEMPLATE="plugin/skills/factory-setup/templates/config.md"

# Output and exit code of the last run_in call.
OUT=""
RC=0

fail() {
  echo "    $*"
  return 1
}

# new_sandbox <name>: fresh git repo with copies of the runners; prints its path.
new_sandbox() {
  local dir="$TMP_ROOT/$1"
  mkdir -p "$dir/scripts"
  git -C "$dir" init -q
  cp "$REPO_ROOT/scripts/test.sh" "$REPO_ROOT/scripts/lint.sh" "$dir/scripts/"
  printf '%s\n' "$dir"
}

# plant <path> <body>: write an executable script.
plant() {
  printf '%s\n' "$2" >"$1"
  chmod +x "$1"
}

# run_in <cwd> <command...>: run a command from <cwd>, capture output and code.
run_in() {
  local cwd="$1"
  shift
  RC=0
  OUT=$(cd "$cwd" && "$@" 2>&1) || RC=$?
}

contains() {
  case "$OUT" in
  *"$1"*) return 0 ;;
  *) return 1 ;;
  esac
}

# --- Feature: One test command ----------------------------------------------

# Scenario: Runs every test script
scenario_runs_every_test_script() {
  local sb log
  sb=$(new_sandbox runs-every)
  log="$sb/order.log"
  plant "$sb/scripts/check.sh" "echo check >>'$log'"
  plant "$sb/scripts/test-b.sh" "echo b >>'$log'"
  plant "$sb/scripts/test-a.sh" "echo a >>'$log'; echo \"\$BASH\" >'$sb/bash.txt'"

  # Run from an unrelated directory to prove test.sh finds its own root.
  run_in "$TMP_ROOT" "$BASH" "$sb/scripts/test.sh"
  [ "$RC" -eq 0 ] || fail "expected exit 0, got $RC: $OUT" || return 1
  [ "$(tr '\n' ' ' <"$log")" = "check a b " ] ||
    fail "expected order 'check a b', got '$(tr '\n' ' ' <"$log")'" || return 1
  [ "$(cat "$sb/bash.txt")" = "$BASH" ] ||
    fail "child ran with '$(cat "$sb/bash.txt")', expected '$BASH'" || return 1
  contains "PASS scripts/check.sh" || fail "missing PASS line for check.sh: $OUT" || return 1
  contains "PASS scripts/test-a.sh" || fail "missing PASS line for test-a.sh: $OUT" || return 1
  contains "PASS scripts/test-b.sh" || fail "missing PASS line for test-b.sh: $OUT" || return 1
  [ "$(printf '%s\n' "$OUT" | tail -n 1)" = "3/3 test scripts passed" ] ||
    fail "unexpected summary line: $(printf '%s\n' "$OUT" | tail -n 1)" || return 1
}

# Scenario: A failing script fails the run but the others still run
scenario_failing_script_does_not_stop_others() {
  local sb
  sb=$(new_sandbox failing)
  plant "$sb/scripts/test-1.sh" "exit 1"
  plant "$sb/scripts/test-2.sh" "touch '$sb/second-ran'"

  run_in "$sb" "$BASH" scripts/test.sh
  [ "$RC" -ne 0 ] || fail "expected non-zero exit: $OUT" || return 1
  [ -f "$sb/second-ran" ] || fail "second script did not run" || return 1
  contains "FAIL scripts/test-1.sh (exit 1)" || fail "missing FAIL line: $OUT" || return 1
  contains "PASS scripts/test-2.sh" || fail "missing PASS line: $OUT" || return 1
  contains "1/2 test scripts passed" || fail "missing summary: $OUT" || return 1
}

# Scenario: No tests is a failure, not a pass
scenario_no_tests_is_failure() {
  local sb
  sb=$(new_sandbox no-tests)
  plant "$sb/scripts/check.sh" "exit 0"

  run_in "$sb" "$BASH" scripts/test.sh
  [ "$RC" -ne 0 ] || fail "expected non-zero exit: $OUT" || return 1
  contains "no test scripts found" || fail "missing 'no test scripts found': $OUT" || return 1
}

# Scenario: Paid or slow runners are never picked up
scenario_run_evals_never_picked_up() {
  local sb
  sb=$(new_sandbox no-evals)
  plant "$sb/scripts/test-ok.sh" "exit 0"
  plant "$sb/scripts/run-evals.sh" "touch '$sb/evals-ran'; exit 1"

  run_in "$sb" "$BASH" scripts/test.sh
  [ "$RC" -eq 0 ] || fail "expected exit 0, got $RC: $OUT" || return 1
  [ ! -e "$sb/evals-ran" ] || fail "run-evals.sh was run" || return 1
  if contains "run-evals"; then fail "output mentions run-evals: $OUT"; return 1; fi
  contains "1/1 test scripts passed" || fail "missing summary: $OUT" || return 1
}

# --- Feature: One lint command ----------------------------------------------

# Scenario: Lints every shell script in the repo (bash -n half)
# Uses real shellcheck when installed; otherwise a pass-through stub so the
# failure can only come from `bash -n`.
scenario_lint_fails_on_syntax_error() {
  local sb path
  sb=$(new_sandbox lint-syntax)
  path="$PATH"
  if ! command -v shellcheck >/dev/null 2>&1; then
    mkdir -p "$sb/.stub"
    plant "$sb/.stub/shellcheck" "exit 0"
    path="$sb/.stub:$PATH"
  fi
  mkdir -p "$sb/nested"
  plant "$sb/nested/good.sh" '#!/usr/bin/env bash
echo "fine"'

  run_in "$TMP_ROOT" env PATH="$path" "$BASH" "$sb/scripts/lint.sh"
  [ "$RC" -eq 0 ] || fail "clean untracked scripts should lint, got $RC: $OUT" || return 1

  plant "$sb/nested/broken.sh" '#!/usr/bin/env bash
if then fi'
  run_in "$TMP_ROOT" env PATH="$path" "$BASH" "$sb/scripts/lint.sh"
  [ "$RC" -ne 0 ] || fail "expected non-zero exit for syntax error: $OUT" || return 1
  contains "broken.sh" || fail "output does not name broken.sh: $OUT" || return 1
}

# Scenario: Lints every shell script in the repo (shellcheck half)
scenario_lint_fails_on_shellcheck_warning() {
  local sb
  if ! command -v shellcheck >/dev/null 2>&1; then
    echo "    skip: shellcheck not installed"
    return 0
  fi
  sb=$(new_sandbox lint-shellcheck)
  # Valid syntax, but SC2086 (unquoted expansion). The literal $1 is intended.
  # shellcheck disable=SC2016
  plant "$sb/warn.sh" '#!/usr/bin/env bash
echo $1'

  run_in "$sb" "$BASH" scripts/lint.sh
  [ "$RC" -ne 0 ] || fail "expected non-zero exit for shellcheck warning: $OUT" || return 1
  contains "SC2086" || fail "expected SC2086 in output: $OUT" || return 1
}

# Scenario: Lints every shell script in the repo (ignored files are skipped)
scenario_lint_skips_ignored_files() {
  local sb
  if ! command -v shellcheck >/dev/null 2>&1; then
    echo "    skip: shellcheck not installed"
    return 0
  fi
  sb=$(new_sandbox lint-ignored)
  printf 'ignored/\n' >"$sb/.gitignore"
  mkdir -p "$sb/ignored"
  plant "$sb/ignored/broken.sh" 'if then fi'

  run_in "$sb" "$BASH" scripts/lint.sh
  [ "$RC" -eq 0 ] || fail "ignored script should not be linted, got $RC: $OUT" || return 1
}

# Scenario: shellcheck missing
scenario_lint_without_shellcheck() {
  local sb bin tool
  sb=$(new_sandbox lint-missing)
  bin="$sb/.bin"
  mkdir -p "$bin"
  for tool in git dirname; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
  done

  run_in "$sb" env PATH="$bin" "$BASH" scripts/lint.sh
  [ "$RC" -ne 0 ] || fail "expected non-zero exit without shellcheck: $OUT" || return 1
  contains "shellcheck is not installed (macOS: brew install shellcheck; Debian/Ubuntu: apt-get install shellcheck)" ||
    fail "missing install hint: $OUT" || return 1
}

# --- Feature: This repo's config --------------------------------------------

# Scenario: Template copied before the config is filled (structure half; the
# byte-for-byte comparison with HEAD's blank template is review evidence)
scenario_template_is_blank() {
  local labels expected line value extra
  [ -f "$TEMPLATE" ] || fail "$TEMPLATE is missing" || return 1

  extra=$(cd plugin/skills/factory-setup && find . -type f ! -path ./templates/config.md ! -name SKILL.md ! -name reference.md)
  [ -z "$extra" ] || fail "unexpected files in plugin/skills/factory-setup: $extra" || return 1

  labels=$(grep -E '^\| \*\*' "$TEMPLATE" | sed -E 's/^\| \*\*([^*]+)\*\*.*/\1/' | tr '\n' ',')
  expected="Install,Test,Lint,Type check,Build,Format,"
  [ "$labels" = "$expected" ] || fail "template Commands labels '$labels' != '$expected'" || return 1

  while IFS= read -r line; do
    value=$(printf '%s\n' "$line" | awk -F'|' '{ gsub(/^ +| +$/, "", $3); print $3 }')
    case "$value" in
    '<!--'*'-->') ;;
    *) fail "template Commands value is not a placeholder: $line"; return 1 ;;
    esac
  done <<EOF
$(grep -E '^\| \*\*' "$TEMPLATE")
EOF

  while IFS= read -r line; do
    case "$line" in
    *': <!--'*'-->') ;;
    *) fail "template field is not a placeholder: $line"; return 1 ;;
    esac
  done <<EOF
$(grep -E '^- \*\*' "$TEMPLATE")
EOF
}

# Scenario: Config points the Verifier at the runners
scenario_config_points_verifier_at_runners() {
  local labels expected needle
  labels=$(grep -E '^\| \*\*' "$CONFIG" | sed -E 's/^\| \*\*([^*]+)\*\*.*/\1/' | tr '\n' ',')
  expected="Install,Test,Lint,Type check,Build,Format,"
  [ "$labels" = "$expected" ] || fail "config Commands labels '$labels' != '$expected'" || return 1

  while IFS= read -r needle; do
    [ -n "$needle" ] || continue
    grep -qF -- "$needle" "$CONFIG" || fail "config is missing: $needle" || return 1
  done <<'EOF'
## Tech Stack
## Project Structure
## Commands
## Conventions
## Architecture Notes
| Check | Command | Notes |
- **Language**: Markdown, Bash
- **Runtime**: bash 3.2+ (macOS `/bin/bash`)
- **Framework**: Claude Code and Cursor skills and subagents
- **Package Manager**: none
- **Source directory**: `plugin/` (from a later task on; `.ai-factory/framework/` until then)
- **Test directory**: `scripts/test-*.sh`
| **Install** | `brew install shellcheck` (macOS) or `apt-get install shellcheck` |
| **Test** | `/bin/bash scripts/test.sh` |
| **Lint** | `/bin/bash scripts/lint.sh` |
| **Type check** | `none` |
| **Build** | `none` |
| **Format** | <!--
- **Commit style**: Conventional Commits
- **Test naming**: one `scripts/test-<area>.sh` per area, one function per scenario
- **Entry point**: <!--
- **Config files**: <!--
- **Code style**: <!--
- **Naming**: <!--
- **Import style**: <!--
Every task adds or extends a `scripts/test-*.sh` file for its scenarios; `scripts/test.sh` runs them all. Tests assert lasting results, never a diff or a commit. A task that intentionally changes something an earlier test asserts updates that test in the same change. Tests never touch the real `$HOME` or make paid model calls.
EOF
}

# Scenario: Configured commands pass (lint half; the test half is this whole
# run, which the Verifier executes via scripts/test.sh)
scenario_configured_lint_passes() {
  run_in "$REPO_ROOT" "$BASH" scripts/lint.sh
  [ "$RC" -eq 0 ] || fail "configured lint command failed ($RC): $OUT" || return 1
}

# --- Runner -------------------------------------------------------------------

repo_state() {
  git -C "$REPO_ROOT" status --porcelain --untracked-files=all
}

SCENARIOS="
scenario_runs_every_test_script
scenario_failing_script_does_not_stop_others
scenario_no_tests_is_failure
scenario_run_evals_never_picked_up
scenario_lint_fails_on_syntax_error
scenario_lint_fails_on_shellcheck_warning
scenario_lint_skips_ignored_files
scenario_lint_without_shellcheck
scenario_template_is_blank
scenario_config_points_verifier_at_runners
scenario_configured_lint_passes
"

before=$(repo_state)
failures=0
for s in $SCENARIOS; do
  if "$s"; then
    echo "ok - $s"
  else
    echo "not ok - $s"
    failures=$((failures + 1))
  fi
done

# Scenario: Harness self-test — the real repository is never modified.
if [ "$(repo_state)" = "$before" ]; then
  echo "ok - real repository unchanged"
else
  echo "not ok - real repository unchanged"
  failures=$((failures + 1))
fi

[ "$failures" -eq 0 ]
