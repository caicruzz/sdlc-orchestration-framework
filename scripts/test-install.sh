#!/usr/bin/env bash
# T007 tests: install.sh (install, upgrade, link mode, uninstall).
# T008 tests: install.sh destination warnings (CLAUDE_CONFIG_DIR, symlinked
# destinations, old ~/.cursor copies).
#
# Isolation: every case runs against a temporary copy of this repository
# (tracked and untracked-but-not-ignored files, committed once as a clean git
# repository) and a fresh temporary HOME under ${TMPDIR:-/tmp}. The real
# $HOME/.claude/agents, $HOME/.claude/skills and $HOME/.claude/.soloaifactory
# are listed (with checksums, without following symlinks) at start and end;
# any difference fails the run.
#
# One function per scenario; each check prints "ok <check>" or "FAIL <check>".
# Exits non-zero if any check fails. bash 3.2 compatible.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd -P)"
real_home="$HOME"
# The caller's CLAUDE_CONFIG_DIR must not affect any case: cases that need it
# set it on one invocation only (run_install_cfg).
unset CLAUDE_CONFIG_DIR

tmp_root="${TMPDIR:-/tmp}"
tmp_root="${tmp_root%/}"
if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then
  echo "abort: temporary directory ${TMPDIR:-/tmp} is not usable" >&2
  exit 1
fi

FAILED=0
ok() { echo "ok   $*"; }
bad() {
  echo "FAIL $*"
  FAILED=1
}
check() {
  local desc="$1"
  shift
  if "$@"; then ok "$desc"; else bad "$desc"; fi
}

AGENTS="factory-architect.md factory-coder.md factory-evaluator.md factory-planner.md factory-reviewer.md factory-verifier.md"
SKILLS="factory-archive factory-build factory-design factory-plan factory-setup"
USAGE="Usage: install.sh [--link] [--uninstall] [--force]"
NEXT_STEP="start a new Claude Code session, or restart Cursor, then say 'set up the factory in this repo'"

# --- Real HOME guard ------------------------------------------------------

# Listing of the real install paths: type, path, and a checksum for regular
# files or the link target for symlinks. Never follows symlinks.
real_home_listing() {
  local p
  {
    find -P "$real_home/.claude/agents" "$real_home/.claude/skills" "$real_home/.claude/.soloaifactory" 2>/dev/null || true
  } | LC_ALL=C sort | while IFS= read -r p; do
    if [ -L "$p" ]; then
      printf 'L %s -> %s\n' "$p" "$(readlink "$p")"
    elif [ -f "$p" ]; then
      printf 'F %s %s\n' "$p" "$(cksum <"$p")"
    elif [ -d "$p" ]; then
      printf 'D %s\n' "$p"
    else
      printf '? %s\n' "$p"
    fi
  done
}
real_listing_start="$(real_home_listing)"

# --- Temporary workspace and repository copy -------------------------------

tmp="$(mktemp -d "$tmp_root/sif-test.XXXXXX")"
cleanup() {
  local h
  # The case HOMEs live next to $tmp, each under the temporary directory.
  if [ -f "$tmp/homes" ]; then
    while IFS= read -r h; do
      case "$h" in "$tmp_root"/sif-home.*) rm -rf -- "$h" ;; esac
    done <"$tmp/homes"
  fi
  rm -rf -- "$tmp"
}
trap cleanup EXIT

# install.sh runs through `#!/usr/bin/env bash`: put the bash running this
# test first on PATH so install.sh is exercised by the same bash (3.2 on macOS).
mkdir "$tmp/bin"
ln -s "$BASH" "$tmp/bin/bash"
PATH="$tmp/bin:$PATH"
export PATH

copy="$tmp/copy"
mkdir "$copy"
(cd "$repo" && git ls-files -z --cached --others --exclude-standard) >"$tmp/files"
while IFS= read -r -d '' f; do
  case "$f" in */) continue ;; esac # nested repositories (e.g. worktrees)
  if [ ! -f "$repo/$f" ] && [ ! -L "$repo/$f" ]; then continue; fi # deleted from the working tree
  mkdir -p "$copy/$(dirname "$f")"
  cp -pR "$repo/$f" "$copy/$f"
done <"$tmp/files"
git -C "$copy" init -q
git -C "$copy" add -A
git -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false \
  -c core.hooksPath=/dev/null -C "$copy" commit -qm fixture
copy="$(cd "$copy" && pwd -P)"

# --- Helpers ----------------------------------------------------------------

abort() {
  echo "abort: $*" >&2
  exit 1
}

# guard_home <dir>: refuse any HOME that is not a fresh directory under the
# temporary directory, or that is the real HOME.
guard_home() {
  case "$1" in
    "$tmp_root"/*) ;;
    *) abort "case HOME $1 is not under $tmp_root" ;;
  esac
  [ "$1" != "$real_home" ] || abort "case HOME equals the real HOME"
}

new_home() {
  local h
  h="$(mktemp -d "$tmp_root/sif-home.XXXXXX")"
  guard_home "$h"
  # Track it for cleanup.
  printf '%s\n' "$h" >>"$tmp/homes"
  printf '%s' "$h"
}

# run_install <case_home> [args...]: sets OUT (stdout+stderr) and RC.
run_install() {
  local case_home="$1"
  shift
  guard_home "$case_home"
  RC=0
  # CLAUDE_CONFIG_DIR is removed here too, so even an exported value can
  # never reach a case that needs it absent.
  OUT="$(env -u CLAUDE_CONFIG_DIR HOME="$case_home" "$copy/install.sh" "$@" 2>&1)" || RC=$?
}

# run_install_cfg <case_home> <CLAUDE_CONFIG_DIR value> [args...]: like
# run_install, with CLAUDE_CONFIG_DIR set for this one invocation.
run_install_cfg() {
  local case_home="$1" cfg="$2"
  shift 2
  guard_home "$case_home"
  RC=0
  OUT="$(CLAUDE_CONFIG_DIR="$cfg" HOME="$case_home" "$copy/install.sh" "$@" 2>&1)" || RC=$?
}

contains() { case "$OUT" in *"$1"*) return 0 ;; esac; return 1; }
lacks() { ! contains "$1"; }
# in_text <text> <needle>
in_text() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
# count_of <needle>: number of lines of $OUT that contain <needle>.
count_of() { printf '%s\n' "$OUT" | grep -cF -- "$1" || true; }
# first_line_starts <prefix>: the first line of $OUT starts with <prefix>, so
# nothing (no report line) was printed before it.
first_line_starts() { case "${OUT%%$'\n'*}" in "$1"*) return 0 ;; esac; return 1; }
is_empty_dir() { [ -d "$1" ] && [ -z "$(entries "$1")" ]; }

# tree_sig <dir>: names, types and checksums under <dir>, without following
# symlinks; paths are relative to <dir>.
tree_sig() {
  local d="$1" p rel
  (cd "$d" && find -P . | LC_ALL=C sort) | while IFS= read -r p; do
    rel="${p#./}"
    if [ -L "$d/$rel" ]; then
      printf 'L %s -> %s\n' "$rel" "$(readlink "$d/$rel")"
    elif [ -f "$d/$rel" ]; then
      printf 'F %s %s\n' "$rel" "$(cksum <"$d/$rel")"
    else
      printf 'D %s\n' "$rel"
    fi
  done
}

# installed_matches <case_home>: exactly the 6 agents and 5 skills, as real
# files and directories identical to <clone>/plugin.
installed_matches() {
  local h="$1" clone="${2:-$copy}" a s
  for a in $AGENTS; do
    if [ ! -f "$h/.claude/agents/$a" ] || [ -L "$h/.claude/agents/$a" ]; then return 1; fi
    cmp -s "$clone/plugin/agents/$a" "$h/.claude/agents/$a" || return 1
  done
  for s in $SKILLS; do
    if [ ! -d "$h/.claude/skills/$s" ] || [ -L "$h/.claude/skills/$s" ]; then return 1; fi
    diff -r "$clone/plugin/skills/$s" "$h/.claude/skills/$s" >/dev/null || return 1
  done
  [ "$(factory_names "$h/.claude/agents")" = "$AGENTS" ] || return 1
  [ "$(factory_names "$h/.claude/skills")" = "$SKILLS" ]
}

# factory_names <dir>: space-separated factory-* names in <dir>, glob order.
factory_names() {
  local p out=""
  for p in "$1"/factory-*; do
    if [ -e "$p" ] || [ -L "$p" ]; then out="$out ${p##*/}"; fi
  done
  printf '%s' "${out# }"
}

# entry_count <dir>: number of entries in <dir>, dotfiles included.
entry_count() {
  local p n=0
  for p in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    if [ -e "$p" ] || [ -L "$p" ]; then n=$((n + 1)); fi
  done
  printf '%s' "$n"
}

# entries <dir>: space-separated names in <dir>, dotfiles included, C order.
entries() {
  local p out=""
  for p in "$1"/.[!.]* "$1"/..?* "$1"/*; do
    if [ -e "$p" ] || [ -L "$p" ]; then out="$out ${p##*/}"; fi
  done
  printf '%s' "${out# }"
}

is_link_to() { [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; }
gone() { [ ! -e "$1" ] && [ ! -L "$1" ]; }

nothing_installed() {
  local h="$1" a s
  for a in $AGENTS; do
    if [ -e "$h/.claude/agents/$a" ] || [ -L "$h/.claude/agents/$a" ]; then return 1; fi
  done
  for s in $SKILLS; do
    if [ -e "$h/.claude/skills/$s" ] || [ -L "$h/.claude/skills/$s" ]; then return 1; fi
  done
  return 0
}

stamp_value() { sed -n "s/^$2=//p" "$1/.claude/.soloaifactory"; }

clone_clean() { [ -z "$(git -C "$1" status --porcelain)" ]; }

# A separate copy of the clone, for cases that change it.
new_clone() {
  local c
  c="$(mktemp -d "$tmp/clone.XXXXXX")"
  rmdir "$c"
  cp -pR "$copy" "$c"
  (cd "$c" && pwd -P)
}

# --- Scenarios ----------------------------------------------------------------

# Scenario: Usage errors
scenario_usage_errors() {
  echo "# Usage errors"
  local h args err outf rc
  for args in "--bogus" "--link --uninstall"; do
    h="$(new_home)"
    guard_home "$h"
    err="$tmp/usage.err"
    outf="$tmp/usage.out"
    rc=0
    # shellcheck disable=SC2086 # split the argument list on purpose
    HOME="$h" "$copy/install.sh" $args >"$outf" 2>"$err" || rc=$?
    check "install.sh $args exits 2" test "$rc" -eq 2
    check "install.sh $args prints the usage line to stderr" grep -qxF "$USAGE" "$err"
    check "install.sh $args writes nothing to stdout" test ! -s "$outf"
    check "install.sh $args writes nothing under HOME" is_empty_dir "$h"
  done
}

# Scenario: Run with `sh`
scenario_run_with_sh() {
  echo "# Run with sh"
  local h rc out shell
  for shell in sh dash; do
    command -v "$shell" >/dev/null 2>&1 || continue
    h="$(new_home)"
    guard_home "$h"
    rc=0
    out="$(HOME="$h" "$shell" "$copy/install.sh" 2>&1)" || rc=$?
    check "$shell install.sh exits 1" test "$rc" -eq 1
    OUT="$out"
    check "$shell install.sh says to run ./install.sh or bash install.sh" contains "run ./install.sh or bash install.sh"
    check "$shell install.sh writes nothing" is_empty_dir "$h"
  done
  h="$(new_home)"
  guard_home "$h"
  rc=0
  out="$(HOME="$h" "$BASH" --posix "$copy/install.sh" 2>&1)" || rc=$?
  OUT="$out"
  check "bash --posix install.sh exits 1" test "$rc" -eq 1
  check "bash --posix install.sh says to run ./install.sh or bash install.sh" contains "run ./install.sh or bash install.sh"
  check "bash --posix install.sh writes nothing" is_empty_dir "$h"
}

# Scenario: Run outside a clone
scenario_outside_clone() {
  echo "# Run outside a clone"
  local h lone
  lone="$tmp/lone"
  mkdir -p "$lone"
  cp -p "$copy/install.sh" "$lone/install.sh"
  h="$(new_home)"
  guard_home "$h"
  RC=0
  OUT="$(HOME="$h" "$lone/install.sh" 2>&1)" || RC=$?
  check "exits 1" test "$RC" -eq 1
  check "says to run install.sh from a soloAIfactory clone" contains "run install.sh from a soloAIfactory clone"
  check "writes nothing" is_empty_dir "$h"
}

# Scenario: HOME unset or empty
scenario_home_unset() {
  echo "# HOME unset or empty"
  RC=0
  OUT="$(cd "$tmp" && HOME="" "$copy/install.sh" 2>&1)" || RC=$?
  check "empty HOME exits 1" test "$RC" -eq 1
  check "empty HOME says HOME is not set" contains "HOME is not set"
  RC=0
  OUT="$(cd "$tmp" && env -u HOME "$copy/install.sh" 2>&1)" || RC=$?
  check "unset HOME exits 1" test "$RC" -eq 1
  check "unset HOME says HOME is not set" contains "HOME is not set"
  check "the clone is unchanged" clone_clean "$copy"
  check "nothing is written in the current directory" test ! -e "$tmp/.claude"
}

# Scenario: HOME unset or empty (Round 1: a relative HOME is refused the same way)
scenario_home_relative() {
  echo "# HOME relative"
  local cwd
  cwd="$tmp/relative-home"
  mkdir -p "$cwd"
  RC=0
  OUT="$(cd "$cwd" && HOME=. "$copy/install.sh" 2>&1)" || RC=$?
  check "HOME=. exits 1" test "$RC" -eq 1
  check "HOME=. says HOME must be an absolute path" contains "HOME must be an absolute path"
  check "HOME=. creates no .claude in the current directory" test ! -e "$cwd/.claude"
  check "HOME=. writes nothing in the current directory" is_empty_dir "$cwd"
  RC=0
  OUT="$(cd "$cwd" && HOME=relative/home "$copy/install.sh" --uninstall 2>&1)" || RC=$?
  check "HOME=relative/home --uninstall exits 1" test "$RC" -eq 1
  check "HOME=relative/home says HOME must be an absolute path" contains "HOME must be an absolute path"
  check "HOME=relative/home writes nothing in the current directory" is_empty_dir "$cwd"
  check "the clone is unchanged" clone_clean "$copy"
}

# Scenario: Any current directory works
scenario_any_cwd() {
  echo "# Any current directory works"
  local h other
  other="$tmp/other-repo"
  mkdir -p "$other"
  git -C "$other" init -q
  echo hello >"$other/file.txt"
  git -C "$other" add file.txt
  git -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false \
    -c core.hooksPath=/dev/null -C "$other" commit -qm init
  h="$(new_home)"
  guard_home "$h"
  RC=0
  OUT="$(cd "$other" && HOME="$h" "$copy/install.sh" 2>&1)" || RC=$?
  check "exits 0" test "$RC" -eq 0
  check "installs from the clone's plugin/" installed_matches "$h"
  check "the stamp names the clone as source" test "$(stamp_value "$h" source)" = "$copy"
  check "the other repository stays clean" clone_clean "$other"
  check "the other repository gains no files" test "$(entries "$other")" = ".git file.txt"
  check "HOME holds only .claude" test "$(entries "$h")" = ".claude"
  check "the clone stays clean" clone_clean "$copy"
}

# Scenario: First install
scenario_first_install() {
  echo "# First install"
  local h
  h="$(new_home)"
  run_install "$h"
  check "exits 0" test "$RC" -eq 0
  check "6 agents and 5 skills identical to plugin/" installed_matches "$h"
  check "agents/ holds only the 6 agents" test "$(entry_count "$h/.claude/agents")" = 6
  check "skills/ holds only the 5 skills" test "$(entry_count "$h/.claude/skills")" = 5
  check "no evals directory is installed" test -z "$(find "$h" -name evals)"
  check "no .claude-plugin directory is installed" test -z "$(find "$h" -name .claude-plugin)"
  check "no staging directory remains" test ! -e "$h/.claude/.soloaifactory-staging"
  check "nothing else under .claude" test "$(entries "$h/.claude")" = ".soloaifactory agents skills"
  check "HOME holds only .claude" test "$(entries "$h")" = ".claude"
}

# Scenario: Stamp contents
scenario_stamp_contents() {
  echo "# Stamp contents"
  local h keys sha
  h="$(new_home)"
  run_install "$h"
  check "exits 0" test "$RC" -eq 0
  keys="$(sed 's/=.*//' "$h/.claude/.soloaifactory" | tr '\n' ' ')"
  check "exactly the keys commit dirty source mode installed agents skills" \
    test "$keys" = "commit dirty source mode installed agents skills "
  sha="$(git -C "$copy" rev-parse HEAD)"
  check "commit is the clone's 40-char HEAD" test "$(stamp_value "$h" commit)" = "$sha"
  check "commit has 40 hex characters" grep -qE '^commit=[0-9a-f]{40}$' "$h/.claude/.soloaifactory"
  check "dirty=false" test "$(stamp_value "$h" dirty)" = false
  check "source is the clone's absolute path" test "$(stamp_value "$h" source)" = "$copy"
  check "mode=copy" test "$(stamp_value "$h" mode)" = copy
  check "installed is a UTC ISO 8601 timestamp" \
    grep -qE '^installed=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$h/.claude/.soloaifactory"
  check "agents= lists the 6 agents sorted" test "$(stamp_value "$h" agents)" = "$AGENTS"
  check "skills= lists the 5 skills sorted" test "$(stamp_value "$h" skills)" = "$SKILLS"
}

# Scenario: Dirty flag
scenario_dirty_flag() {
  echo "# Dirty flag"
  local h c
  c="$(new_clone)"
  echo "local edit" >>"$c/README.md"
  h="$(new_home)"
  guard_home "$h"
  RC=0
  OUT="$(HOME="$h" "$c/install.sh" 2>&1)" || RC=$?
  check "dirty clone: exits 0" test "$RC" -eq 0
  check "dirty clone: stamp has dirty=true" test "$(stamp_value "$h" dirty)" = true
  check "dirty clone: report says the clone had uncommitted changes" contains "uncommitted changes"
  check "dirty clone: report does not say clean" lacks "no uncommitted changes"

  c="$(new_clone)"
  rm -rf -- "$c/.git"
  h="$(new_home)"
  guard_home "$h"
  RC=0
  OUT="$(HOME="$h" "$c/install.sh" 2>&1)" || RC=$?
  check "outside git: exits 0" test "$RC" -eq 0
  check "outside git: commit=unknown" test "$(stamp_value "$h" commit)" = unknown
  check "outside git: dirty=false" test "$(stamp_value "$h" dirty)" = false
  check "outside git: installs the clone's plugin/" installed_matches "$h" "$c"
}

# Scenario: Idempotent re-run
scenario_idempotent() {
  echo "# Idempotent re-run"
  local h first second
  h="$(new_home)"
  run_install "$h"
  first="$(tree_sig "$h/.claude/agents")$(tree_sig "$h/.claude/skills")"
  run_install "$h"
  check "second run exits 0" test "$RC" -eq 0
  second="$(tree_sig "$h/.claude/agents")$(tree_sig "$h/.claude/skills")"
  check "files and contents are identical after the second run" test "$first" = "$second"
  check "second run removes nothing" lacks "removed "
}

# Scenario: Report
scenario_report() {
  echo "# Report"
  local h a s
  h="$(new_home)"
  mkdir -p "$h/.claude/agents"
  echo planted >"$h/.claude/agents/factory-gone.md"
  printf 'agents=factory-gone.md\nskills=\n' >"$h/.claude/.soloaifactory"
  echo planted >"$h/.claude/agents/factory-mine.md"
  run_install "$h"
  check "exits 0" test "$RC" -eq 0
  for a in $AGENTS; do check "lists agent $a" contains "$a"; done
  for s in $SKILLS; do check "lists skill $s" contains "$s"; done
  check "gives the commit" contains "$(git -C "$copy" rev-parse HEAD)"
  check "says whether the clone had uncommitted changes" contains "no uncommitted changes"
  check "gives the mode" contains "mode: copy"
  check "lists each removed path" contains "removed $h/.claude/agents/factory-gone.md"
  check "gives the left-in-place notice" contains "$h/.claude/agents/factory-mine.md: not installed by soloAIfactory; left in place"
  check "gives the next step" contains "$NEXT_STEP"
}

# Scenario: Entries listed in the previous stamp are removed when dropped upstream
scenario_stamp_listed_removed() {
  echo "# Entries listed in the previous stamp are removed when dropped upstream"
  local h
  h="$(new_home)"
  run_install "$h"
  printf 'commit=unknown\ndirty=false\nagents=%s factory-old.md\nskills=%s factory-old\n' "$AGENTS" "$SKILLS" \
    >"$h/.claude/.soloaifactory"
  echo old >"$h/.claude/agents/factory-old.md"
  mkdir -p "$h/.claude/skills/factory-old"
  echo old >"$h/.claude/skills/factory-old/SKILL.md"
  run_install "$h"
  check "exits 0" test "$RC" -eq 0
  check "agents/factory-old.md is removed" test ! -e "$h/.claude/agents/factory-old.md"
  check "skills/factory-old is removed" test ! -e "$h/.claude/skills/factory-old"
  check "the removed agent path is printed" contains "removed $h/.claude/agents/factory-old.md"
  check "the removed skill path is printed" contains "removed $h/.claude/skills/factory-old"
  check "the current set is installed" installed_matches "$h"
}

# Scenario: Unlisted factory-* entries are kept
scenario_unlisted_kept() {
  echo "# Unlisted factory-* entries are kept"
  local h
  h="$(new_home)"
  run_install "$h"
  echo mine >"$h/.claude/agents/factory-mine.md"
  run_install "$h"
  check "exits 0" test "$RC" -eq 0
  check "factory-mine.md is kept" grep -qx mine "$h/.claude/agents/factory-mine.md"
  check "factory-mine.md is reported as left in place" \
    contains "$h/.claude/agents/factory-mine.md: not installed by soloAIfactory; left in place"
  check "factory-mine.md is not reported as removed" lacks "removed $h/.claude/agents/factory-mine.md"
}

# Scenario: Unlisted factory-* entries are kept (Round 1: a damaged stamp
# naming a glob is never expanded against the current directory)
scenario_damaged_stamp_glob() {
  echo "# Damaged stamp with a glob name"
  local h cwd
  h="$(new_home)"
  guard_home "$h"
  mkdir -p "$h/.claude/agents"
  printf 'agents=factory-*\nskills=factory-*\n' >"$h/.claude/.soloaifactory"
  echo mine >"$h/.claude/agents/factory-zzz.md"
  cwd="$tmp/glob-cwd"
  mkdir -p "$cwd"
  echo decoy >"$cwd/factory-zzz.md"
  RC=0
  OUT="$(cd "$cwd" && HOME="$h" "$copy/install.sh" 2>&1)" || RC=$?
  check "exits 0" test "$RC" -eq 0
  check "the user's factory-zzz.md is kept" grep -qx mine "$h/.claude/agents/factory-zzz.md"
  check "factory-zzz.md is reported as left in place" \
    contains "$h/.claude/agents/factory-zzz.md: not installed by soloAIfactory; left in place"
  check "factory-zzz.md is not reported as removed" lacks "removed $h/.claude/agents/factory-zzz.md"
  check "the decoy in the current directory is unchanged" grep -qx decoy "$cwd/factory-zzz.md"
  check "the current directory gains no files" test "$(entries "$cwd")" = "factory-zzz.md"
  check "the current set is installed" test "$(stamp_value "$h" agents)" = "$AGENTS"
}

# Scenario: `--force` removes unlisted factory-* entries
scenario_force_removes_unlisted() {
  echo "# --force removes unlisted factory-* entries"
  local h
  h="$(new_home)"
  run_install "$h"
  echo mine >"$h/.claude/agents/factory-mine.md"
  run_install "$h" --force
  check "exits 0" test "$RC" -eq 0
  check "factory-mine.md is removed" test ! -e "$h/.claude/agents/factory-mine.md"
  check "the removed path is printed" contains "removed $h/.claude/agents/factory-mine.md"
  check "the current set is installed" installed_matches "$h"
}

# Scenario: No previous stamp: shipped names are replaced, other factory-*
# entries are kept (they may be the user's own)
scenario_no_stamp_replaces_all() {
  echo "# No previous stamp: shipped names replaced, other factory-* entries kept"
  local h
  h="$(new_home)"
  mkdir -p "$h/.claude/agents" "$h/.claude/skills/factory-mine"
  echo mine >"$h/.claude/agents/factory-mine.md"
  echo mine >"$h/.claude/skills/factory-mine/SKILL.md"
  echo stale >"$h/.claude/agents/factory-coder.md"
  run_install "$h"
  check "exits 0" test "$RC" -eq 0
  check "agents/factory-mine.md is kept" grep -qx mine "$h/.claude/agents/factory-mine.md"
  check "skills/factory-mine is kept" grep -qx mine "$h/.claude/skills/factory-mine/SKILL.md"
  check "agents/factory-mine.md is reported as left in place" \
    contains "$h/.claude/agents/factory-mine.md: not installed by soloAIfactory; left in place"
  check "skills/factory-mine is reported as left in place" \
    contains "$h/.claude/skills/factory-mine: not installed by soloAIfactory; left in place"
  check "agents/factory-mine.md is not reported as removed" lacks "removed $h/.claude/agents/factory-mine.md"
  check "skills/factory-mine is not reported as removed" lacks "removed $h/.claude/skills/factory-mine"
  check "the stale factory-coder.md is replaced" \
    cmp -s "$copy/plugin/agents/factory-coder.md" "$h/.claude/agents/factory-coder.md"
  check "the stamp lists only the shipped agents" test "$(stamp_value "$h" agents)" = "$AGENTS"
}

# Scenario: No previous stamp with --force removes other factory-* entries
scenario_no_stamp_force() {
  echo "# No previous stamp with --force removes other factory-* entries"
  local h
  h="$(new_home)"
  mkdir -p "$h/.claude/agents" "$h/.claude/skills/factory-mine"
  echo mine >"$h/.claude/agents/factory-mine.md"
  echo mine >"$h/.claude/skills/factory-mine/SKILL.md"
  run_install "$h" --force
  check "exits 0" test "$RC" -eq 0
  check "agents/factory-mine.md is removed" test ! -e "$h/.claude/agents/factory-mine.md"
  check "skills/factory-mine is removed" test ! -e "$h/.claude/skills/factory-mine"
  check "the removed agent path is printed" contains "removed $h/.claude/agents/factory-mine.md"
  check "the removed skill path is printed" contains "removed $h/.claude/skills/factory-mine"
  check "the 6 agents and 5 skills are installed" installed_matches "$h"
}

# Scenario: --uninstall with no stamp removes the shipped names and keeps
# other factory-* entries; --force removes those too
scenario_no_stamp_uninstall() {
  echo "# --uninstall with no stamp removes shipped names, keeps others"
  local h a s
  h="$(new_home)"
  run_install "$h"
  rm -f "$h/.claude/.soloaifactory"
  echo mine >"$h/.claude/agents/factory-mine.md"
  mkdir -p "$h/.claude/skills/factory-mine"
  echo mine >"$h/.claude/skills/factory-mine/SKILL.md"
  run_install "$h" --uninstall
  check "exits 0" test "$RC" -eq 0
  check "the 6 agents and 5 skills are removed" nothing_installed "$h"
  for a in $AGENTS; do check "prints removed agents/$a" contains "removed $h/.claude/agents/$a"; done
  for s in $SKILLS; do check "prints removed skills/$s" contains "removed $h/.claude/skills/$s"; done
  check "agents/factory-mine.md is kept" grep -qx mine "$h/.claude/agents/factory-mine.md"
  check "skills/factory-mine is kept" grep -qx mine "$h/.claude/skills/factory-mine/SKILL.md"
  check "agents/factory-mine.md is reported as left in place" \
    contains "$h/.claude/agents/factory-mine.md: not installed by soloAIfactory; left in place"
  check "skills/factory-mine is reported as left in place" \
    contains "$h/.claude/skills/factory-mine: not installed by soloAIfactory; left in place"

  run_install "$h" --uninstall --force
  check "--force: exits 0" test "$RC" -eq 0
  check "--force: agents/factory-mine.md is removed" test ! -e "$h/.claude/agents/factory-mine.md"
  check "--force: skills/factory-mine is removed" test ! -e "$h/.claude/skills/factory-mine"
}

# Scenario: --uninstall with a damaged stamp that lists no names falls back to
# the shipped names, so one run removes the install
scenario_damaged_stamp_uninstall() {
  echo "# --uninstall with a stamp that lists no names"
  local h
  h="$(new_home)"
  run_install "$h"
  printf 'mode=copy\n' >"$h/.claude/.soloaifactory"
  run_install "$h" --uninstall
  check "exits 0" test "$RC" -eq 0
  check "the 6 agents and 5 skills are removed" nothing_installed "$h"
  check "the stamp is removed" test ! -e "$h/.claude/.soloaifactory"
  check "no shipped entry is reported as left in place" lacks "not installed by soloAIfactory; left in place"
}

# Scenario: Non-factory entries are never touched
scenario_non_factory_untouched() {
  echo "# Non-factory entries are never touched"
  local h before args
  h="$(new_home)"
  mkdir -p "$h/.claude/agents" "$h/.claude/skills/other"
  echo mine >"$h/.claude/agents/mine.md"
  echo other >"$h/.claude/skills/other/SKILL.md"
  before="$(tree_sig "$h/.claude/agents" | grep -v factory-)$(tree_sig "$h/.claude/skills" | grep -v factory-)"
  for args in "" "--force" "--uninstall --force"; do
    # shellcheck disable=SC2086 # split the argument list on purpose
    run_install "$h" $args
    check "install.sh $args exits 0" test "$RC" -eq 0
    check "mine.md and skills/other/ unchanged after install.sh $args" test \
      "$(tree_sig "$h/.claude/agents" | grep -v factory-)$(tree_sig "$h/.claude/skills" | grep -v factory-)" = "$before"
  done
}

# Scenario: Shell options do not change the outcome
#
# Note: bash before 4.1 ignores BASHOPTS from the environment, so under macOS
# /bin/bash (3.2) the BASHOPTS cases run with default options and only the
# SHELLOPTS=noglob case changes anything. When a bash 4.1 or newer is found
# (newer_bash), the BASHOPTS cases run again under it, where they take effect.
scenario_shell_options() {
  echo "# Shell options do not change the outcome"
  local opts nb
  for opts in "" "SHELLOPTS=noglob" "BASHOPTS=nullglob" "BASHOPTS=failglob"; do
    shell_options_case "$opts" ""
  done
  nb="$(newer_bash)"
  if [ -n "$nb" ]; then
    for opts in "BASHOPTS=nullglob" "BASHOPTS=failglob"; do
      shell_options_case "$opts" "$nb"
    done
  else
    ok "no bash 4.1 or newer found; BASHOPTS cases under a newer bash skipped"
  fi
}

# shell_options_case <env assignment or empty> <bash to run install.sh with,
# or empty for its own #! line>
shell_options_case() {
  local opts="$1" sh="$2" h label
  label="${opts:-(default options)}${sh:+ under $sh}"
  h="$(new_home)"
  guard_home "$h"
  mkdir -p "$h/.claude/agents" "$h/.claude/skills"
  RC=0
  # shellcheck disable=SC2086 # an empty $opts or $sh adds no argument
  OUT="$(env $opts HOME="$h" $sh "$copy/install.sh" 2>&1)" || RC=$?
  check "install $label: exits 0" test "$RC" -eq 0
  check "install $label: installs the full set" installed_matches "$h"
  check "install $label: no literal factory-* reported" lacks 'factory-*'
  check "install $label: no literal factory-* created" \
    test -z "$(find "$h" -name 'factory-\*')"
  RC=0
  # shellcheck disable=SC2086 # an empty $opts or $sh adds no argument
  OUT="$(env $opts HOME="$h" $sh "$copy/install.sh" --uninstall 2>&1)" || RC=$?
  check "uninstall $label: exits 0" test "$RC" -eq 0
  check "uninstall $label: no literal factory-* reported" lacks 'factory-*'
  check "uninstall $label: everything removed" nothing_installed "$h"
}

# newer_bash: path of a bash 4.1 or newer on PATH or in a usual place, or
# nothing. The bash shim in $tmp/bin is skipped.
newer_bash() {
  local b v
  for b in $(type -ap bash) /opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash /bin/bash; do
    case "$b" in "$tmp"/*) continue ;; esac
    [ -x "$b" ] || continue
    # shellcheck disable=SC2016 # expanded by the bash being probed
    v="$("$b" -c 'echo $((BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1]))' 2>/dev/null || true)"
    case "$v" in '' | *[!0-9]*) continue ;; esac
    if [ "$v" -ge 401 ]; then
      printf '%s' "$b"
      return 0
    fi
  done
  return 0
}

# Scenario: `--link` installs symlinks into the clone
scenario_link_installs_symlinks() {
  echo "# --link installs symlinks into the clone"
  local h a s
  h="$(new_home)"
  run_install "$h" --link
  check "exits 0" test "$RC" -eq 0
  for a in $AGENTS; do
    check "agents/$a is a symlink into the clone" is_link_to "$h/.claude/agents/$a" "$copy/plugin/agents/$a"
  done
  for s in $SKILLS; do
    check "skills/$s is a symlink into the clone" is_link_to "$h/.claude/skills/$s" "$copy/plugin/skills/$s"
  done
  check "the stamp has mode=link" test "$(stamp_value "$h" mode)" = link
  check "the report gives mode: link" contains "mode: link"
}

# Scenario: Link then copy leaves the clone intact
scenario_link_then_copy() {
  echo "# Link then copy leaves the clone intact"
  local h before
  h="$(new_home)"
  before="$(tree_sig "$copy/plugin")"
  run_install "$h" --link
  run_install "$h"
  check "copy run exits 0" test "$RC" -eq 0
  check "installed entries are real files and directories again" installed_matches "$h"
  check "the stamp has mode=copy" test "$(stamp_value "$h" mode)" = copy
  check "the clone's git status is empty" clone_clean "$copy"
  check "the clone's plugin/ is byte-identical" test "$(tree_sig "$copy/plugin")" = "$before"
}

# Scenario: Link then uninstall leaves the clone intact
scenario_link_then_uninstall() {
  echo "# Link then uninstall leaves the clone intact"
  local h before
  h="$(new_home)"
  before="$(tree_sig "$copy/plugin")"
  run_install "$h" --link
  run_install "$h" --uninstall
  check "uninstall exits 0" test "$RC" -eq 0
  check "the symlinks are gone" nothing_installed "$h"
  check "the stamp is gone" test ! -e "$h/.claude/.soloaifactory"
  check "the clone's git status is empty" clone_clean "$copy"
  check "the clone's plugin/ is byte-identical" test "$(tree_sig "$copy/plugin")" = "$before"
}

# Scenario: Leftover staging directory from an interrupted run
scenario_leftover_staging() {
  echo "# Leftover staging directory from an interrupted run"
  local h before staging
  before="$(tree_sig "$copy/plugin")"

  h="$(new_home)"
  staging="$h/.claude/.soloaifactory-staging"
  mkdir -p "$staging/agents" "$staging/skills"
  echo stale >"$staging/agents/factory-coder.md"
  ln -s "$copy/plugin" "$staging/plugin"
  ln -s "$copy/plugin/skills/factory-build" "$staging/skills/factory-build"
  run_install "$h"
  check "staging dir with symlinks: exits 0" test "$RC" -eq 0
  check "staging dir with symlinks: install completes" installed_matches "$h"
  check "staging dir with symlinks: no staging directory remains" gone "$staging"
  check "staging dir with symlinks: the clone is unchanged" test "$(tree_sig "$copy/plugin")" = "$before"
  check "staging dir with symlinks: the clone's git status is empty" clone_clean "$copy"

  h="$(new_home)"
  staging="$h/.claude/.soloaifactory-staging"
  mkdir -p "$h/.claude"
  ln -s "$copy/plugin" "$staging"
  run_install "$h"
  check "staging symlink: exits 0" test "$RC" -eq 0
  check "staging symlink: install completes" installed_matches "$h"
  check "staging symlink: no staging directory remains" gone "$staging"
  check "staging symlink: the clone is unchanged" test "$(tree_sig "$copy/plugin")" = "$before"
  check "staging symlink: the clone's git status is empty" clone_clean "$copy"
}

# Scenario: Uninstall removes what the stamp lists
scenario_uninstall() {
  echo "# Uninstall removes what the stamp lists"
  local h a s before
  h="$(new_home)"
  run_install "$h"
  echo mine >"$h/.claude/agents/factory-mine.md"
  echo mine >"$h/.claude/agents/mine.md"
  mkdir -p "$h/.claude/skills/other"
  echo other >"$h/.claude/skills/other/SKILL.md"
  before="$(tree_sig "$h/.claude/agents" | grep -v factory-)$(tree_sig "$h/.claude/skills" | grep -v factory-)"
  run_install "$h" --uninstall
  check "exits 0" test "$RC" -eq 0
  check "the 6 agents and 5 skills are removed" nothing_installed "$h"
  check "the stamp is removed" test ! -e "$h/.claude/.soloaifactory"
  for a in $AGENTS; do check "prints removed agents/$a" contains "removed $h/.claude/agents/$a"; done
  for s in $SKILLS; do check "prints removed skills/$s" contains "removed $h/.claude/skills/$s"; done
  check "prints the removed stamp" contains "removed $h/.claude/.soloaifactory"
  check "factory-mine.md is kept" test -f "$h/.claude/agents/factory-mine.md"
  check "factory-mine.md is reported as left in place" \
    contains "$h/.claude/agents/factory-mine.md: not installed by soloAIfactory; left in place"
  check "mine.md and skills/other/ are unchanged" test \
    "$(tree_sig "$h/.claude/agents" | grep -v factory-)$(tree_sig "$h/.claude/skills" | grep -v factory-)" = "$before"
}

# --- T008: destination warnings ------------------------------------------------

CURSOR_WARNING="these take priority over this install in Cursor; remove them"

# cfg_warning <CLAUDE_CONFIG_DIR value>: the sentence the warning must contain.
cfg_warning() { printf 'Claude Code reads %s, so it will not see this install; Cursor will' "$1"; }

# Scenario: CLAUDE_CONFIG_DIR points elsewhere
scenario_cfg_elsewhere() {
  echo "# CLAUDE_CONFIG_DIR points elsewhere"
  local h cfg
  h="$(new_home)"
  cfg="$h/other-config"
  mkdir -p "$cfg"
  run_install_cfg "$h" "$cfg"
  check "existing dir: exits 0" test "$RC" -eq 0
  check "existing dir: warns that Claude Code reads CLAUDE_CONFIG_DIR" contains "$(cfg_warning "$cfg")"
  check "existing dir: the warning names both paths" contains "CLAUDE_CONFIG_DIR is $cfg, not $h/.claude"
  check "existing dir: the warning is printed before anything else" first_line_starts "warning: CLAUDE_CONFIG_DIR is $cfg"
  check "existing dir: the install goes to \$HOME/.claude" installed_matches "$h"
  check "existing dir: CLAUDE_CONFIG_DIR gains nothing" is_empty_dir "$cfg"
  check "existing dir: HOME holds only .claude and the config dir" test "$(entries "$h")" = ".claude other-config"

  h="$(new_home)"
  cfg="$h/missing-config"
  run_install_cfg "$h" "$cfg"
  check "missing dir: exits 0" test "$RC" -eq 0
  check "missing dir: warns that Claude Code reads CLAUDE_CONFIG_DIR" contains "$(cfg_warning "$cfg")"
  check "missing dir: the warning is printed before anything else" first_line_starts "warning: CLAUDE_CONFIG_DIR is $cfg"
  check "missing dir: the install goes to \$HOME/.claude" installed_matches "$h"
  check "missing dir: CLAUDE_CONFIG_DIR is not created" gone "$cfg"
}

# Scenario: CLAUDE_CONFIG_DIR points at the default location
scenario_cfg_default() {
  echo "# CLAUDE_CONFIG_DIR points at the default location"
  local h cfg label
  for label in "exact, before install" "trailing slashes, before install" \
    "exact, after install" "trailing slash, after install" "symlink" "symlink with trailing slash"; do
    h="$(new_home)"
    case "$label" in
      "exact, before install") cfg="$h/.claude" ;;
      "trailing slashes, before install") cfg="$h/.claude//" ;;
      "exact, after install")
        mkdir -p "$h/.claude"
        cfg="$h/.claude"
        ;;
      "trailing slash, after install")
        mkdir -p "$h/.claude"
        cfg="$h/.claude/"
        ;;
      "symlink")
        mkdir -p "$h/.claude"
        ln -s "$h/.claude" "$h/cfg-link"
        cfg="$h/cfg-link"
        ;;
      "symlink with trailing slash")
        mkdir -p "$h/.claude"
        ln -s "$h/.claude" "$h/cfg-link"
        cfg="$h/cfg-link/"
        ;;
    esac
    run_install_cfg "$h" "$cfg"
    check "$label: exits 0" test "$RC" -eq 0
    check "$label: no CLAUDE_CONFIG_DIR warning" lacks "CLAUDE_CONFIG_DIR"
    check "$label: no warning at all" lacks "warning"
    check "$label: installs into \$HOME/.claude" installed_matches "$h"
  done
}

# Scenario: The skills or agents directory is a symlink
scenario_symlinked_destination() {
  echo "# The skills or agents directory is a symlink"
  local h kind target n
  for kind in skills agents; do
    h="$(new_home)"
    mkdir -p "$h/dotfiles/$kind" "$h/.claude"
    ln -s "$h/dotfiles/$kind" "$h/.claude/$kind"
    target="$(cd "$h/dotfiles/$kind" && pwd -P)"
    run_install "$h"
    check "$kind: exits 0" test "$RC" -eq 0
    check "$kind: warns with the resolved symlink target" contains "$h/.claude/$kind is a symlink to $target"
    check "$kind: the warning is printed before anything else" first_line_starts "warning: $h/.claude/$kind is a symlink"
    check "$kind: \$HOME/.claude/$kind is still the same symlink" is_link_to "$h/.claude/$kind" "$h/dotfiles/$kind"
    if [ "$kind" = skills ]; then
      for n in $SKILLS; do
        check "skills: $n lands in the symlink target" test -d "$h/dotfiles/skills/$n" -a ! -L "$h/dotfiles/skills/$n"
      done
    else
      for n in $AGENTS; do
        check "agents: $n lands in the symlink target" test -f "$h/dotfiles/agents/$n" -a ! -L "$h/dotfiles/agents/$n"
      done
    fi
    check "$kind: the full set is installed" installed_matches "$h"
  done
}

# Scenario: Old Cursor copies would take priority
scenario_cursor_copies() {
  echo "# Old Cursor copies would take priority"
  local h before nl=$'\n'
  h="$(new_home)"
  mkdir -p "$h/.cursor/agents" "$h/.cursor/skills/factory-old"
  echo old >"$h/.cursor/agents/factory-x.md"
  echo old >"$h/.cursor/skills/factory-old/SKILL.md"
  echo mine >"$h/.cursor/agents/mine.md"
  before="$(tree_sig "$h/.cursor")"
  run_install "$h"
  check "agent and skill: exits 0" test "$RC" -eq 0
  check "agent and skill: prints the Cursor warning" contains "$CURSOR_WARNING"
  check "agent and skill: the warning is followed by each path" \
    contains "$CURSOR_WARNING:$nl  $h/.cursor/agents/factory-x.md$nl  $h/.cursor/skills/factory-old$nl"
  check "agent and skill: the warning is printed before anything else" first_line_starts "warning: $CURSOR_WARNING"
  check "agent and skill: a non-factory Cursor file is not listed" lacks "$h/.cursor/agents/mine.md"
  check "agent and skill: \$HOME/.cursor is byte-identical" test "$(tree_sig "$h/.cursor")" = "$before"
  check "agent and skill: the install completes" installed_matches "$h"

  h="$(new_home)"
  mkdir -p "$h/.cursor/skills" "$h/elsewhere"
  ln -s "$h/elsewhere" "$h/.cursor/skills/factory-linked"
  before="$(tree_sig "$h/.cursor")"
  run_install "$h"
  check "skill symlink only: exits 0" test "$RC" -eq 0
  check "skill symlink only: the warning lists the path" \
    contains "$CURSOR_WARNING:$nl  $h/.cursor/skills/factory-linked$nl"
  check "skill symlink only: \$HOME/.cursor is byte-identical" test "$(tree_sig "$h/.cursor")" = "$before"
  check "skill symlink only: the install completes" installed_matches "$h"
}

# Scenario: No warning conditions
scenario_no_warnings() {
  echo "# No warning conditions"
  local h
  h="$(new_home)"
  run_install "$h"
  check "first install: exits 0" test "$RC" -eq 0
  check "first install: no warning" lacks "warning"
  check "first install: no repeated-warnings section" lacks "Warnings and notices"
  mkdir -p "$h/.cursor/agents"
  echo mine >"$h/.cursor/agents/mine.md"
  run_install "$h"
  check "re-run with only non-factory Cursor files: exits 0" test "$RC" -eq 0
  check "re-run with only non-factory Cursor files: no warning" lacks "warning"
  run_install "$h" --uninstall
  check "uninstall: exits 0" test "$RC" -eq 0
  check "uninstall: no warning" lacks "warning"
}

# Scenario: Warnings are repeated in the final report
scenario_warnings_repeated() {
  echo "# Warnings are repeated in the final report"
  local h cfg target report text
  h="$(new_home)"
  cfg="$h/other-config"
  mkdir -p "$cfg" "$h/dotfiles/skills" "$h/.claude" "$h/.cursor/agents"
  ln -s "$h/dotfiles/skills" "$h/.claude/skills"
  target="$(cd "$h/dotfiles/skills" && pwd -P)"
  run_install "$h"
  echo mine >"$h/.claude/agents/factory-mine.md"
  echo old >"$h/.cursor/agents/factory-x.md"
  run_install_cfg "$h" "$cfg"
  check "install: exits 0" test "$RC" -eq 0
  report="${OUT#*soloAIfactory installed into}"
  check "install: the report has a repeated-warnings section" in_text "$report" "Warnings and notices (repeated from above):"
  for text in "$(cfg_warning "$cfg")" \
    "$h/.claude/skills is a symlink to $target" \
    "$CURSOR_WARNING" \
    "$h/.cursor/agents/factory-x.md" \
    "$h/.claude/agents/factory-mine.md: not installed by soloAIfactory; left in place"; do
    check "install: printed once before and once in the report: $text" test "$(count_of "$text")" -eq 2
    check "install: the report repeats: $text" in_text "$report" "$text"
  done

  run_install_cfg "$h" "$cfg" --uninstall
  check "uninstall: exits 0" test "$RC" -eq 0
  report="${OUT#*soloAIfactory uninstalled from}"
  for text in "$(cfg_warning "$cfg")" \
    "$CURSOR_WARNING" \
    "$h/.cursor/agents/factory-x.md" \
    "$h/.claude/agents/factory-mine.md: not installed by soloAIfactory; left in place"; do
    check "uninstall: printed once before and once in the report: $text" test "$(count_of "$text")" -eq 2
    check "uninstall: the report repeats: $text" in_text "$report" "$text"
  done
}

# Scenario: Uninstall warns the same way
scenario_uninstall_warns() {
  echo "# Uninstall warns the same way"
  local h before nl=$'\n'
  h="$(new_home)"
  run_install "$h"
  mkdir -p "$h/.cursor/agents"
  echo old >"$h/.cursor/agents/factory-x.md"
  before="$(tree_sig "$h/.cursor")"
  run_install "$h" --uninstall
  check "installed: exits 0" test "$RC" -eq 0
  check "installed: prints the Cursor warning with the path" \
    contains "$CURSOR_WARNING:$nl  $h/.cursor/agents/factory-x.md$nl"
  check "installed: the warning is printed before anything else" first_line_starts "warning: $CURSOR_WARNING"
  check "installed: \$HOME/.cursor is untouched" test "$(tree_sig "$h/.cursor")" = "$before"
  check "installed: the factory set is removed" nothing_installed "$h"

  h="$(new_home)"
  mkdir -p "$h/.cursor/agents"
  echo old >"$h/.cursor/agents/factory-x.md"
  before="$(tree_sig "$h/.cursor")"
  run_install "$h" --uninstall
  check "not installed: exits 0" test "$RC" -eq 0
  check "not installed: prints the Cursor warning with the path" \
    contains "$CURSOR_WARNING:$nl  $h/.cursor/agents/factory-x.md$nl"
  check "not installed: says soloAIfactory is not installed" contains "soloAIfactory is not installed"
  check "not installed: \$HOME/.cursor is untouched" test "$(tree_sig "$h/.cursor")" = "$before"
  check "not installed: no .claude is created" gone "$h/.claude"
}

# Scenario: New cases use the existing harness
scenario_warning_isolation() {
  echo "# New cases use the existing harness"
  local h out
  check "the harness runs with CLAUDE_CONFIG_DIR unset" test -z "${CLAUDE_CONFIG_DIR+x}"
  h="$(new_home)"
  run_install_cfg "$h" "$h/other-config"
  check "run_install_cfg sets CLAUDE_CONFIG_DIR for that invocation" contains "$(cfg_warning "$h/other-config")"
  check "run_install_cfg does not leave CLAUDE_CONFIG_DIR set" test -z "${CLAUDE_CONFIG_DIR+x}"
  h="$(new_home)"
  out="$(
    CLAUDE_CONFIG_DIR=/nonexistent/caller-config
    export CLAUDE_CONFIG_DIR
    run_install "$h"
    printf '%s' "$OUT"
  )"
  OUT="$out"
  check "a caller's exported CLAUDE_CONFIG_DIR does not reach run_install" lacks "CLAUDE_CONFIG_DIR"
  check "every case HOME is under the temporary directory" \
    test -z "$(grep -v "^$tmp_root/sif-home\." "$tmp/homes" || true)"
}

# Scenario: Tests run only against a temporary copy and a temporary HOME
scenario_test_isolation() {
  echo "# Tests run only against a temporary copy and a temporary HOME"
  case "$copy" in
    "$repo" | "$repo"/*) bad "the copy is outside the repository" ;;
    *) ok "the copy is outside the repository" ;;
  esac
  check "the copy is a git repository with one commit" test "$(git -C "$copy" rev-list --count HEAD)" = 1
  check "the copy is clean" clone_clean "$copy"
  check "the copy has install.sh" test -x "$copy/install.sh"
  if guard_home_probe "$real_home"; then bad "guard_home refuses the real HOME"; else ok "guard_home refuses the real HOME"; fi
  if guard_home_probe /nonexistent/home; then
    bad "guard_home refuses a path outside the temporary directory"
  else
    ok "guard_home refuses a path outside the temporary directory"
  fi
  check "guard_home accepts a fresh temporary HOME" guard_home_probe "$(new_home)"
}
# Runs guard_home in a subshell, so its abort only ends the subshell.
guard_home_probe() { (guard_home "$1") 2>/dev/null; }

# Scenario: Generated adapters are deleted in the same change as the installer
scenario_adapters_removed() {
  echo "# Generated adapters are deleted in the same change as the installer"
  check "git ls-files .claude .cursor prints nothing" test -z "$(git -C "$repo" ls-files .claude .cursor)"
}

# Scenario: Installer is tracked as executable
scenario_installer_executable() {
  echo "# Installer is tracked as executable"
  check "install.sh is tracked with mode 100755" test "$(git -C "$repo" ls-files -s install.sh | cut -d' ' -f1)" = 100755
  check "scripts/test-install.sh is executable" test -x "$repo/scripts/test-install.sh"
}

# Scenario: Shellcheck clean
scenario_shellcheck() {
  echo "# Shellcheck clean"
  if ! command -v shellcheck >/dev/null 2>&1; then
    ok "shellcheck not installed; skipped (scripts/lint.sh enforces it)"
    return 0
  fi
  check "shellcheck install.sh scripts/test-install.sh reports nothing" \
    test -z "$(cd "$copy" && shellcheck install.sh scripts/test-install.sh 2>&1)"
}

for scenario in \
  scenario_test_isolation \
  scenario_usage_errors \
  scenario_run_with_sh \
  scenario_outside_clone \
  scenario_home_unset \
  scenario_home_relative \
  scenario_any_cwd \
  scenario_first_install \
  scenario_stamp_contents \
  scenario_dirty_flag \
  scenario_idempotent \
  scenario_report \
  scenario_stamp_listed_removed \
  scenario_unlisted_kept \
  scenario_damaged_stamp_glob \
  scenario_force_removes_unlisted \
  scenario_no_stamp_replaces_all \
  scenario_no_stamp_force \
  scenario_no_stamp_uninstall \
  scenario_damaged_stamp_uninstall \
  scenario_non_factory_untouched \
  scenario_shell_options \
  scenario_link_installs_symlinks \
  scenario_link_then_copy \
  scenario_link_then_uninstall \
  scenario_leftover_staging \
  scenario_uninstall \
  scenario_cfg_elsewhere \
  scenario_cfg_default \
  scenario_symlinked_destination \
  scenario_cursor_copies \
  scenario_no_warnings \
  scenario_warnings_repeated \
  scenario_uninstall_warns \
  scenario_warning_isolation \
  scenario_adapters_removed \
  scenario_installer_executable \
  scenario_shellcheck; do
  if ! "$scenario"; then bad "$scenario stopped early"; fi
done

# Scenario: Real HOME guard (checked at the end of every run)
echo "# Real HOME guard"
check "HOME is unchanged" test "$HOME" = "$real_home"
real_listing_end="$(real_home_listing)"
if [ "$real_listing_start" = "$real_listing_end" ]; then
  ok "real ~/.claude/agents, ~/.claude/skills and ~/.claude/.soloaifactory are unchanged"
else
  bad "real ~/.claude/agents, ~/.claude/skills and ~/.claude/.soloaifactory are unchanged"
  diff <(printf '%s\n' "$real_listing_start") <(printf '%s\n' "$real_listing_end") || true
fi

if [ "$FAILED" -ne 0 ]; then
  echo "test-install: FAILED"
  exit 1
fi
echo "test-install: all checks passed"
