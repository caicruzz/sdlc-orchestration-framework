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
# Bare assignment so set -e stops the run if mktemp fails; canonicalise in a
# separate step (macOS: /var -> /private/var). The EXIT trap deletes TMP_ROOT,
# so install it only once TMP_ROOT is known to be a fresh directory that is
# neither the repository, inside it, nor a parent of it.
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-harness.XXXXXX")
TMP_ROOT=$(cd "$TMP_ROOT" && pwd -P)
unsafe_tmp_root() {
  [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ] || return 0
  case "$TMP_ROOT" in
  / | "$REPO_ROOT" | "$REPO_ROOT"/*) return 0 ;;
  esac
  case "$REPO_ROOT" in
  "$TMP_ROOT"/*) return 0 ;;
  esac
  return 1
}
if unsafe_tmp_root; then
  echo "refusing to use temporary directory '$TMP_ROOT': it must be a fresh directory outside $REPO_ROOT" >&2
  # Remove it only if it is the empty directory mktemp just made.
  if [ -n "$TMP_ROOT" ]; then rmdir "$TMP_ROOT" 2>/dev/null || true; fi
  exit 1
fi
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

# stub_shellcheck <dir>: install a pass-through shellcheck in <dir>/.stub and
# print a PATH that finds it first.
stub_shellcheck() {
  mkdir -p "$1/.stub"
  plant "$1/.stub/shellcheck" "exit 0"
  printf '%s\n' "$1/.stub:$PATH"
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
# A pass-through stub always replaces shellcheck here, so the planted
# syntax error can only be caught by lint.sh's `bash -n` step.
scenario_lint_fails_on_syntax_error() {
  local sb path
  sb=$(new_sandbox lint-syntax)
  path=$(stub_shellcheck "$sb")
  mkdir -p "$sb/nested"
  plant "$sb/nested/good.sh" '#!/usr/bin/env bash
echo "fine"'

  run_in "$TMP_ROOT" env PATH="$path" "$BASH" "$sb/scripts/lint.sh"
  [ "$RC" -eq 0 ] || fail "clean untracked scripts should lint, got $RC: $OUT" || return 1

  plant "$sb/nested/broken.sh" '#!/usr/bin/env bash
if then fi'
  run_in "$TMP_ROOT" env PATH="$path" "$BASH" "$sb/scripts/lint.sh"
  [ "$RC" -ne 0 ] || fail "expected non-zero exit for syntax error: $OUT" || return 1
  contains "FAIL bash -n nested/broken.sh" ||
    fail "output does not report the bash -n failure for nested/broken.sh: $OUT" || return 1
  if contains "FAIL shellcheck"; then fail "stubbed shellcheck should not fail: $OUT"; return 1; fi
}

# Scenario: Lints every shell script in the repo (names git would C-quote, such
# as ones with a double quote or a tab, are linted too). shellcheck is stubbed
# so only `bash -n` can catch the planted syntax errors.
scenario_lint_covers_quoted_file_names() {
  local sb path quoted tabbed
  sb=$(new_sandbox lint-quoted)
  path=$(stub_shellcheck "$sb")
  quoted='we"ird.sh'
  tabbed=$(printf 'tab\there.sh')
  plant "$sb/$quoted" 'if then fi'
  plant "$sb/$tabbed" 'if then fi'

  run_in "$sb" env PATH="$path" "$BASH" scripts/lint.sh
  [ "$RC" -ne 0 ] || fail "expected non-zero exit for broken scripts with quoted names: $OUT" || return 1
  contains "FAIL bash -n $quoted" || fail "script named '$quoted' was not linted: $OUT" || return 1
  contains "FAIL bash -n $tabbed" || fail "script with a tab in its name was not linted: $OUT" || return 1
}

# Scenario: Lints every shell script in the repo (a `git ls-files` failure
# fails the run instead of reading as an empty list)
scenario_lint_fails_when_git_ls_files_fails() {
  local sb path real_git
  sb=$(new_sandbox lint-ls-files)
  path=$(stub_shellcheck "$sb")
  real_git=$(command -v git)
  # Pass everything through to git except ls-files, which fails.
  plant "$sb/.stub/git" "#!/bin/sh
for a in \"\$@\"; do
  [ \"\$a\" = ls-files ] && exit 1
done
exec '$real_git' \"\$@\""

  run_in "$sb" env PATH="$path" "$BASH" scripts/lint.sh
  [ "$RC" -ne 0 ] || fail "expected non-zero exit when git ls-files fails: $OUT" || return 1
  contains "git ls-files failed; cannot list shell scripts to lint" ||
    fail "missing git ls-files failure message: $OUT" || return 1
  if contains "no shell scripts to lint"; then fail "reported nothing to lint: $OUT"; return 1; fi
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

# Scenario: Lints every shell script in the repo (outside a git work tree the
# file list cannot be trusted, so lint.sh fails instead of passing silently)
scenario_lint_fails_outside_git_work_tree() {
  local dir path
  dir="$TMP_ROOT/no-git"
  mkdir -p "$dir/scripts"
  cp "$REPO_ROOT/scripts/lint.sh" "$dir/scripts/"
  plant "$dir/broken.sh" 'if then fi'
  path=$(stub_shellcheck "$dir")

  # Stop git from discovering any repository above the temp root.
  run_in "$dir" env PATH="$path" GIT_CEILING_DIRECTORIES="$TMP_ROOT" "$BASH" scripts/lint.sh
  [ "$RC" -ne 0 ] || fail "expected non-zero exit outside a git work tree: $OUT" || return 1
  contains "must run inside a git work tree" || fail "missing git work tree message: $OUT" || return 1
  if contains "no shell scripts to lint"; then fail "reported nothing to lint: $OUT"; return 1; fi
}

# --- Feature: The runners are themselves tested -----------------------------

# Scenario: Harness self-test (the harness never deletes the repository it
# runs from, even when its temporary directory cannot be made safely).
# A copy of this file runs inside a sandbox, so a regression could only ever
# delete the sandbox. Both cases stop before any scenario runs, so nothing
# recurses.
scenario_harness_refuses_unsafe_tmp_root() {
  local sb
  sb=$(new_sandbox harness-tmp)
  cp "$REPO_ROOT/scripts/test-harness.sh" "$sb/scripts/"
  printf 'keep\n' >"$sb/sentinel"

  # mktemp fails: TMPDIR points at a directory that does not exist.
  run_in "$sb" env TMPDIR="$TMP_ROOT/missing-tmpdir" "$BASH" scripts/test-harness.sh
  [ "$RC" -ne 0 ] || fail "expected non-zero exit when mktemp fails: $OUT" || return 1
  [ -f "$sb/sentinel" ] && [ -f "$sb/scripts/test.sh" ] ||
    fail "sandbox repository was deleted when mktemp failed" || return 1
  if contains "ok - "; then fail "scenarios ran after mktemp failed: $OUT"; return 1; fi

  # mktemp succeeds, but inside the repository: refused, repository intact.
  mkdir -p "$sb/inner-tmp"
  run_in "$sb" env TMPDIR="$sb/inner-tmp" "$BASH" scripts/test-harness.sh
  [ "$RC" -ne 0 ] || fail "expected non-zero exit for a temp dir inside the repo: $OUT" || return 1
  contains "refusing to use temporary directory" || fail "missing refusal message: $OUT" || return 1
  [ -f "$sb/sentinel" ] && [ -f "$sb/scripts/test.sh" ] ||
    fail "sandbox repository was deleted for a temp dir inside it" || return 1
  [ -z "$(ls -A "$sb/inner-tmp")" ] || fail "refused temp dir was left behind in the repo" || return 1
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
scenario_lint_covers_quoted_file_names
scenario_lint_fails_when_git_ls_files_fails
scenario_lint_fails_on_shellcheck_warning
scenario_lint_skips_ignored_files
scenario_lint_without_shellcheck
scenario_lint_fails_outside_git_work_tree
scenario_harness_refuses_unsafe_tmp_root
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
