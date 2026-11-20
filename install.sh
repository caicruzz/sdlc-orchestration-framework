#!/usr/bin/env bash
# Install, upgrade or uninstall soloAIfactory's agents and skills.
#
# Usage: install.sh [--link] [--uninstall] [--force]
#
# Run from a soloAIfactory clone (any current directory works). Copies the
# factory-* agents in plugin/agents/ and the factory-* skill directories in
# plugin/skills/ into $HOME/.claude/agents and $HOME/.claude/skills, where both
# Claude Code and Cursor load them, and records what it installed in
# $HOME/.claude/.soloaifactory (the stamp).
#
#   --link       install symlinks into this clone instead of copies
#   --uninstall  remove what the stamp lists (with no stamp, or none listed
#                for a kind, the factory-* names this clone ships), then the
#                stamp
#   --force      also remove factory-* entries the stamp does not list
#
# Without --force, a factory-* entry that is neither installed by this run nor
# listed in the stamp is reported and left in place, even with no stamp.
#
# Never writes inside a repository, never uses the network, and removes
# nothing that is not a factory-* entry under $HOME/.claude/agents or
# $HOME/.claude/skills (plus its own stamp and staging directory). Removal
# never follows symlinks.
#
# Before writing, warns when the install would not take effect as expected:
# CLAUDE_CONFIG_DIR points away from $HOME/.claude, $HOME/.claude/agents or
# $HOME/.claude/skills is a symlink, or old factory-* copies under
# $HOME/.cursor/agents or $HOME/.cursor/skills would shadow it in Cursor (they
# are listed, never touched). The final report repeats every warning.

# sh guard: must stay the first executable code and POSIX. macOS `sh` is bash
# in POSIX mode with BASH_VERSION set, so check SHELLOPTS too.
if [ -z "${BASH_VERSION:-}" ]; then
  echo "install.sh needs bash: run ./install.sh or bash install.sh" >&2
  exit 1
fi
case ":${SHELLOPTS:-}:" in
  *:posix:*)
    echo "install.sh needs bash outside POSIX mode: run ./install.sh or bash install.sh" >&2
    exit 1
    ;;
esac

set -euo pipefail
# Inherited shell options (SHELLOPTS, BASHOPTS) must not change the outcome.
set +f
shopt -u nullglob failglob nocaseglob nocasematch 2>/dev/null || true
unset CDPATH
LC_ALL=C
export LC_ALL

usage() {
  echo "Usage: install.sh [--link] [--uninstall] [--force]" >&2
  exit 2
}

link=false
uninstall=false
force=false
while [ $# -gt 0 ]; do
  case "$1" in
    --link) link=true ;;
    --uninstall) uninstall=true ;;
    --force) force=true ;;
    *) usage ;;
  esac
  shift
done
if $link && $uninstall; then usage; fi

if [ -z "${HOME:-}" ]; then
  echo "HOME is not set: cannot find the destination \$HOME/.claude" >&2
  exit 1
fi
case "$HOME" in
  /*) ;;
  *)
    echo "HOME must be an absolute path (got '$HOME'): cannot find the destination \$HOME/.claude" >&2
    exit 1
    ;;
esac

root="$(cd "$(dirname "$0")" && pwd -P)"
src="$root/plugin"
if [ ! -d "$src/agents" ] || [ ! -d "$src/skills" ]; then
  echo "run install.sh from a soloAIfactory clone (no plugin/agents or plugin/skills next to $0)" >&2
  exit 1
fi

dest="$HOME/.claude"
agents_dir="$dest/agents"
skills_dir="$dest/skills"
stamp="$dest/.soloaifactory"
staging="$dest/.soloaifactory-staging"

# The only way this script deletes anything. Paths never carry a trailing
# slash, so a symlink is removed itself and never followed.
safe_rm() { if [ -L "$1" ]; then rm -f -- "$1"; elif [ -e "$1" ]; then rm -rf -- "$1"; fi; }

# valid_name <name>: a factory-* name safe to join to a directory and to keep
# in a space-separated list (no slash, space or glob character).
valid_name() {
  case "$1" in
    factory-*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

# in_list <name> <space-separated list>
in_list() {
  valid_name "$1" || return 1
  case " $2 " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# Report lines, collected as newline-separated strings (not arrays: an empty
# array breaks under `set -u` on bash 3.2). Warnings and left-in-place notices
# are printed when they arise and repeated in the final report.
removed_lines=""
kept_lines=""
warn_lines=""
note_removed() { removed_lines="$removed_lines  removed $1"$'\n'; }
note_kept() {
  local l="$1: not installed by soloAIfactory; left in place"
  echo "$l"
  kept_lines="$kept_lines  $l"$'\n'
}
warn() {
  echo "warning: $1" >&2
  warn_lines="$warn_lines  warning: $1"$'\n'
}
# warn_more <line>: a continuation line of the previous warning.
warn_more() {
  echo "  $1" >&2
  warn_lines="$warn_lines    $1"$'\n'
}
report_repeats() {
  if [ -n "$warn_lines$kept_lines" ]; then
    echo "Warnings and notices (repeated from above):"
    printf '%s' "$warn_lines$kept_lines"
  fi
}

# resolve_dir <path>: the physical path of an existing directory, or nothing.
resolve_dir() { (cd -P -- "$1" 2>/dev/null && pwd -P) || true; }
# strip_slashes <path>: <path> without trailing slashes ("/" stays "/").
strip_slashes() {
  local s="$1"
  while [ "${#s}" -gt 1 ] && [ "${s%/}" != "$s" ]; do s="${s%/}"; done
  printf '%s' "$s"
}

# Destination warnings, printed before anything is created, staged or
# removed. They only read: nothing outside $HOME/.claude is ever written, and
# nothing under $HOME/.cursor is ever removed.
check_destination() {
  local cfg="${CLAUDE_CONFIG_DIR:-}" a b d p target where first=true
  if $uninstall; then where="removed from"; else where="installed into"; fi
  # 1. Claude Code reads $CLAUDE_CONFIG_DIR instead of $HOME/.claude.
  if [ -n "$cfg" ]; then
    a="$(resolve_dir "$cfg")"
    b="$(resolve_dir "$dest")"
    if [ -z "$a" ] || [ -z "$b" ]; then
      a="$(strip_slashes "$cfg")"
      b="$(strip_slashes "$dest")"
    fi
    if [ "$a" != "$b" ]; then
      warn "CLAUDE_CONFIG_DIR is $cfg, not $dest: Claude Code reads $cfg, so it will not see this install; Cursor will"
    fi
  fi
  # 2. A symlinked agents or skills directory: entries land in its target.
  for d in "$agents_dir" "$skills_dir"; do
    [ -L "$d" ] || continue
    target="$(resolve_dir "$d")"
    if [ -n "$target" ]; then
      warn "$d is a symlink to $target: the factory-* entries are $where $target"
    else
      warn "$d is a symlink to $(readlink "$d" || true), which is not an existing directory"
    fi
  done
  # 3. Old user-level Cursor copies shadow $HOME/.claude in Cursor.
  for p in "$HOME/.cursor/agents"/factory-* "$HOME/.cursor/skills"/factory-*; do
    if [ ! -e "$p" ] && [ ! -L "$p" ]; then continue; fi
    if $first; then
      warn "these take priority over this install in Cursor; remove them:"
      first=false
    fi
    warn_more "$p"
  done
}

# Shipped sets: the names this clone ships, sorted and space-separated.
ship_agents=""
ship_skills=""
for p in "$src/agents"/factory-*.md; do
  if [ -f "$p" ] && valid_name "${p##*/}"; then ship_agents="$ship_agents ${p##*/}"; fi
done
for p in "$src/skills"/factory-*; do
  if [ -d "$p" ] && valid_name "${p##*/}"; then ship_skills="$ship_skills ${p##*/}"; fi
done
ship_agents="${ship_agents# }"
ship_skills="${ship_skills# }"

# Source sets: what this run installs (nothing on --uninstall).
src_agents=""
src_skills=""
if ! $uninstall; then
  src_agents="$ship_agents"
  src_skills="$ship_skills"
  if [ -z "$src_agents" ] || [ -z "$src_skills" ]; then
    echo "no factory-* agents or skills found under $src" >&2
    exit 1
  fi
fi

# Previous set: names on the stamp's agents= / skills= lines.
prev_agents=""
prev_skills=""
if [ -f "$stamp" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      agents=*) prev_agents="${line#agents=}" ;;
      skills=*) prev_skills="${line#skills=}" ;;
    esac
  done <"$stamp"
fi
# Keep only valid names (a damaged stamp must never name a path outside).
# Globbing is off while the list is split, so a stamp name such as factory-*
# is never expanded against the current directory; valid_name then drops it.
clean_list() {
  local out="" n
  set -f
  for n in $1; do
    if valid_name "$n"; then out="$out $n"; fi
  done
  set +f
  printf '%s' "${out# }"
}
prev_agents="$(clean_list "$prev_agents")"
prev_skills="$(clean_list "$prev_skills")"
# With no stamp, or a damaged one that lists no valid names for a kind,
# --uninstall falls back to the names this clone ships for that kind. An
# install needs no fallback, since it replaces those names anyway.
if $uninstall; then
  if [ -z "$prev_agents" ]; then prev_agents="$ship_agents"; fi
  if [ -z "$prev_skills" ]; then prev_skills="$ship_skills"; fi
fi

check_destination

if $uninstall; then
  if [ ! -d "$dest" ]; then
    echo "soloAIfactory is not installed: $dest does not exist"
    report_repeats
    exit 0
  fi
else
  mkdir -p "$agents_dir" "$skills_dir"
  # Stage the new set next to the destination, so the swap is a rename.
  safe_rm "$staging"
  mkdir -p "$staging/agents" "$staging/skills"
  for n in $src_agents; do
    if $link; then ln -s "$src/agents/$n" "$staging/agents/$n"; else cp -p "$src/agents/$n" "$staging/agents/$n"; fi
  done
  for n in $src_skills; do
    if $link; then ln -s "$src/skills/$n" "$staging/skills/$n"; else cp -pR "$src/skills/$n" "$staging/skills/$n"; fi
  done
fi

# swap_kind <kind> <dir> <staged names> <stamp-listed names>
swap_kind() {
  local kind="$1" dir="$2" staged="$3" listed="$4" n p
  # 1. Put each staged entry in place (the target must be gone before mv,
  #    or mv would nest a directory inside it).
  for n in $staged; do
    safe_rm "$dir/$n"
    mv "$staging/$kind/$n" "$dir/$n"
  done
  # 2. Remove stamp-listed entries that are no longer installed.
  for n in $listed; do
    if in_list "$n" "$staged"; then continue; fi
    if [ -e "$dir/$n" ] || [ -L "$dir/$n" ]; then
      safe_rm "$dir/$n"
      note_removed "$dir/$n"
    fi
  done
  # 3. Any other factory-* entry: removed only with --force, otherwise left
  #    in place, with or without a stamp (it may be the user's own).
  [ -d "$dir" ] || return 0
  for p in "$dir"/factory-*; do
    if [ ! -e "$p" ] && [ ! -L "$p" ]; then continue; fi
    n="${p##*/}"
    if in_list "$n" "$staged" || in_list "$n" "$listed"; then continue; fi
    if $force; then
      safe_rm "$p"
      note_removed "$p"
    else
      note_kept "$p"
    fi
  done
}

swap_kind agents "$agents_dir" "$src_agents" "$prev_agents"
swap_kind skills "$skills_dir" "$src_skills" "$prev_skills"

if $uninstall; then
  if [ -e "$stamp" ] || [ -L "$stamp" ]; then
    safe_rm "$stamp"
    note_removed "$stamp"
  fi
  safe_rm "$staging"
  echo "soloAIfactory uninstalled from $dest"
  if [ -n "$removed_lines" ]; then printf '%s' "$removed_lines"; else echo "  nothing to remove"; fi
  report_repeats
  exit 0
fi

# Stamp values. Only trust git when the clone itself is the repository root,
# and never let git write (no optional index refresh).
commit=unknown
dirty=false
if command -v git >/dev/null 2>&1; then
  top="$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$root" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ] && [ -d "$top" ] && [ "$(cd "$top" && pwd -P)" = "$root" ]; then
    commit="$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$root" rev-parse -q --verify HEAD 2>/dev/null || true)"
    if [ -z "$commit" ]; then commit=unknown; fi
    status="$(env -u GIT_DIR -u GIT_WORK_TREE GIT_OPTIONAL_LOCKS=0 git -C "$root" status --porcelain 2>/dev/null || true)"
    if [ -n "$status" ]; then dirty=true; fi
  fi
fi
mode="copy"
if $link; then mode="link"; fi

tmp_stamp="$(mktemp "$dest/.soloaifactory.XXXXXX")"
trap 'rm -f -- "$tmp_stamp"' EXIT
{
  echo "commit=$commit"
  echo "dirty=$dirty"
  echo "source=$root"
  echo "mode=$mode"
  echo "installed=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "agents=$src_agents"
  echo "skills=$src_skills"
} >"$tmp_stamp"
mv -f "$tmp_stamp" "$stamp"
safe_rm "$staging"

echo "soloAIfactory installed into $dest"
echo "  agents: $src_agents"
echo "  skills: $src_skills"
if $dirty; then
  echo "  commit: $commit (the clone had uncommitted changes)"
else
  echo "  commit: $commit (no uncommitted changes)"
fi
echo "  mode: $mode"
if [ -n "$removed_lines" ]; then printf '%s' "$removed_lines"; fi
report_repeats
echo "Next step: start a new Claude Code session, or restart Cursor, then say 'set up the factory in this repo'"
