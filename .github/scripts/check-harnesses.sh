#!/usr/bin/env bash
# Checks that the per-harness copies in .ai-factory/harnesses/ stay in sync.
#
# Every harness must ship the same agent files and skill files. Frontmatter may
# differ per harness. Below the frontmatter, agent prompts must be identical,
# and skill files must be identical except for the "## Invoking subagents"
# section, which explains the harness's own way to call a subagent.
# Every skill must also carry an identical "## State branch" section.
#
# Requires bash 3.2+ and standard POSIX tools.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS_DIR="$ROOT/.ai-factory/harnesses"
status=0

fail() { echo "check-harnesses: $*" >&2; status=1; }

# body <file> : print the file without its leading YAML frontmatter.
body() {
  awk 'NR == 1 && $0 == "---" { fm = 1; next }
       fm && $0 == "---" { fm = 0; next }
       !fm { print }' "$1"
}

# skill_body <file> : body() minus the "## Invoking subagents" section.
skill_body() {
  body "$1" | awk '/^## / { skip = ($0 == "## Invoking subagents") }
                   !skip { print }'
}

# frontmatter_field <file> <key> : print a top-level frontmatter value. For a
# block scalar (> or |, with optional - or +), print its first content line.
frontmatter_field() {
  awk -v key="$2" 'NR == 1 && $0 == "---" { fm = 1; next }
       fm && $0 == "---" { exit }
       block { if ($0 ~ /^[ \t]+[^ \t]/) { sub(/^[ \t]+/, ""); print }; exit }
       fm && index($0, key ": ") == 1 {
         v = substr($0, length(key) + 3)
         if (v ~ /^[>|][-+]?[ \t]*$/) { block = 1; next }
         print v; exit
       }' "$1"
}

# state_section <file> : print the "## State branch" section of a skill.
state_section() {
  body "$1" | awk '/^## / { keep = ($0 == "## State branch") }
                   keep { print }'
}

# list_files <harness> : relative paths of all agent and skill files.
list_files() {
  (cd "$HARNESS_DIR/$1" && find agents skills -type f | LC_ALL=C sort)
}

harnesses=""
for d in "$HARNESS_DIR"/*/; do
  harnesses="$harnesses $(basename "$d")"
done
set -- $harnesses
[ $# -ge 1 ] || { echo "check-harnesses: no harnesses found" >&2; exit 1; }
ref="$1"
ref_files="$(list_files "$ref")"

for h in "$@"; do
  [ -f "$HARNESS_DIR/$h/INSTALL.md" ] || fail "$h: missing INSTALL.md"
  [ "$(list_files "$h")" = "$ref_files" ] \
    || fail "$h: agent/skill files differ from $ref (add or remove them in every harness)"

  for f in "$HARNESS_DIR/$h"/skills/*/SKILL.md; do
    dir="$(basename "$(dirname "$f")")"
    name="$(frontmatter_field "$f" name)"
    [ "$name" = "$dir" ] || fail "$h: skills/$dir/SKILL.md name '$name' does not match folder"
    [ -n "$(frontmatter_field "$f" description)" ] || fail "$h: skills/$dir/SKILL.md has no description"
  done

  for f in "$HARNESS_DIR/$h"/agents/*.md; do
    file="$(basename "$f" .md)"
    name="$(frontmatter_field "$f" name)"
    # OpenCode-style agents take their name from the filename and omit `name`.
    [ -z "$name" ] || [ "$name" = "$file" ] \
      || fail "$h: agents/$file.md name '$name' does not match filename"
    [ -n "$(frontmatter_field "$f" description)" ] || fail "$h: agents/$file.md has no description"
  done

  [ "$h" = "$ref" ] && continue
  for rel in $ref_files; do
    a="$HARNESS_DIR/$ref/$rel" b="$HARNESS_DIR/$h/$rel"
    [ -f "$b" ] || continue
    case "$rel" in
      agents/*.md)
        diff <(body "$a") <(body "$b") > /dev/null \
          || fail "$h/$rel: prompt differs from $ref/$rel" ;;
      skills/*/SKILL.md)
        diff <(skill_body "$a") <(skill_body "$b") > /dev/null \
          || fail "$h/$rel: content differs from $ref/$rel (outside ## Invoking subagents)" ;;
      *)
        cmp -s "$a" "$b" || fail "$h/$rel: differs from $ref/$rel" ;;
    esac
  done
done

# Every skill carries the same "## State branch" section (it is copied, not
# shared, so each skill stays self-contained). Harness copies are compared
# above, so checking the reference harness covers all of them.
first_state=""
for f in "$HARNESS_DIR/$ref"/skills/*/SKILL.md; do
  dir="$(basename "$(dirname "$f")")"
  section="$(state_section "$f")"
  if [ -z "$section" ]; then
    fail "$ref: skills/$dir/SKILL.md has no ## State branch section"
  elif [ -z "$first_state" ]; then
    first_state="$section" first_dir="$dir"
  elif [ "$section" != "$first_state" ]; then
    fail "$ref: skills/$dir/SKILL.md ## State branch differs from skills/$first_dir/SKILL.md"
  fi
done

if [ "$status" -eq 0 ]; then
  echo "check-harnesses: $# harnesses in sync"
fi
exit "$status"
