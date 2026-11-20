#!/usr/bin/env bash
# Structural checks for this repository (T010).
#
# Guards what a pull request could silently break: the skill and agent
# structure under plugin/, the Verifier contract and the frozen config labels,
# retired paths, the installer's mode and tracked tool directories.
#
# Read-only. Checks the repository that contains this script, whatever the
# current directory. Every rule group runs; each prints "ok   <group>" or
# "FAIL <group>" followed by one indented line per problem (naming the file).
# Exits 1 if any group failed. bash 3.2 compatible; needs only git, grep, sed
# and awk.
set -euo pipefail
cd "$(dirname "$0")/.."

AGENTS_DIR="plugin/agents"
SKILLS_DIR="plugin/skills"
VERIFIER="$AGENTS_DIR/factory-verifier.md"
BUILD="$SKILLS_DIR/factory-build/SKILL.md"
CONFIG_TEMPLATE="$SKILLS_DIR/factory-setup/templates/config.md"

# The frozen Commands labels of the config template, in order, each with its
# Notes when that is exactly "Required". Changing this is a deliberate edit:
# the labels are the contract between factory-setup, the Verifier and
# factory-build.
FROZEN_LABELS="Install=,Test=Required,Lint=Required,Type check=,Build=,Format="

# Agents that may run commands.
BASH_AGENTS="factory-reviewer factory-verifier"

FAILED=0
GROUPS_PASSED=0
PROBLEMS=""

# problem <message>: record one problem for the current rule group.
problem() {
  PROBLEMS="$PROBLEMS  $1
"
}

# finish_group <name>: report the current group and reset its problems.
finish_group() {
  if [ -z "$PROBLEMS" ]; then
    echo "ok   $1"
    GROUPS_PASSED=$((GROUPS_PASSED + 1))
  else
    echo "FAIL $1"
    printf '%s' "$PROBLEMS"
    FAILED=1
  fi
  PROBLEMS=""
}

# --- Parsing helpers ----------------------------------------------------------

# frontmatter <file>: the lines between the first two `---` lines.
frontmatter() {
  awk '/^---[[:space:]]*$/ { n++; if (n == 2) exit; next } n == 1 { print }' "$1"
}

# fm_has <file> <key>: the frontmatter has a top-level <key>: line.
fm_has() {
  frontmatter "$1" | grep -q "^$2:"
}

# fm_value <file> <key>: the inline value of <key>, trimmed and unquoted.
fm_value() {
  frontmatter "$1" | awk -v k="$2" '
    index($0, k ":") == 1 {
      v = substr($0, length(k) + 2)
      sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
      if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
      print v
      exit
    }'
}

# fm_nonempty <file> <key>: <key> has a non-empty value, inline or as an
# indented block (`>`, `>-`, `|` ... followed by indented lines).
fm_nonempty() {
  frontmatter "$1" | awk -v k="$2" '
    found { if ($0 ~ /^[[:space:]]+[^[:space:]]/) ok = 1; exit }
    index($0, k ":") == 1 {
      v = substr($0, length(k) + 2)
      sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
      if (v ~ /^[>|][-+]?$/ || v == "") { found = 1; next }
      if (v != "\"\"" && v != "\047\047") ok = 1
      exit
    }
    END { exit !ok }'
}

# fm_tools <file>: the agent tools, one per line (inline `a, b`, flow `[a, b]`
# or block `- a` lists).
fm_tools() {
  frontmatter "$1" | awk '
    found {
      if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
        t = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", t); sub(/[[:space:]]+$/, "", t)
        if (t != "") print t
        next
      }
      exit
    }
    /^tools:/ {
      found = 1
      v = substr($0, 7)
      gsub(/[][]/, "", v)
      n = split(v, parts, ",")
      for (i = 1; i <= n; i++) {
        t = parts[i]; sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t)
        if (t != "") print t
      }
    }'
}

# table_rows <file> <header prefix>: the data rows of the Markdown table whose
# header line starts with <header prefix> (separator rows skipped).
table_rows() {
  awk -v h="$2" '
    !in_table && index($0, h) == 1 { in_table = 1; next }
    in_table && /^\|/ { if ($0 !~ /^\|[[:space:]]*-/) print; next }
    in_table { exit }' "$1"
}

# cell <row> <n>: the n-th cell of a table row, trimmed.
cell() {
  printf '%s\n' "$1" | awk -F'|' -v n="$2" '{
    v = $(n + 1); sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v); print v }'
}

# bold <text>: the text between the first pair of `**`.
bold() {
  printf '%s\n' "$1" | sed -n 's/^[^*]*\*\*\([^*]*\)\*\*.*/\1/p'
}

# config_rows: "label=Notes" for each Commands row of the config template,
# where Notes is kept only when it is exactly "Required".
config_rows() {
  local row label notes
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    label=$(bold "$(cell "$row" 1)")
    notes=$(cell "$row" 3)
    [ "$notes" = "Required" ] || notes=""
    printf '%s=%s\n' "$label" "$notes"
  done <<EOF
$(table_rows "$CONFIG_TEMPLATE" '| Check | Command | Notes |')
EOF
}

# --- Skill structure ------------------------------------------------------------

check_skill_frontmatter() {
  local d name skill found=0
  for d in "$SKILLS_DIR"/*/; do
    [ -d "$d" ] || continue
    d=${d%/}
    name=${d##*/}
    skill="$d/SKILL.md"
    found=1
    if [ ! -f "$skill" ]; then
      problem "$skill is missing"
      continue
    fi
    if [ "$(fm_value "$skill" name)" != "$name" ]; then
      problem "$skill: frontmatter name is '$(fm_value "$skill" name)', expected '$name'"
    fi
    if ! fm_nonempty "$skill" description; then
      problem "$skill: frontmatter has no description"
    fi
  done
  [ "$found" -eq 1 ] || problem "no skills found under $SKILLS_DIR/"
  finish_group "skill frontmatter (name matches directory, description present)"
}

check_skill_templates() {
  local skill d t
  for skill in "$SKILLS_DIR"/*/SKILL.md; do
    [ -f "$skill" ] || continue
    d=${skill%/SKILL.md}
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      [ -f "$d/$t" ] || problem "$skill names $t, which does not exist in $d/templates/"
    done <<EOF
$(grep -oE '(^|[^A-Za-z0-9_./-])templates/[A-Za-z0-9._-]+\.md' "$skill" | sed 's/^.*templates\//templates\//' | LC_ALL=C sort -u || true)
EOF
  done
  finish_group "skill templates (every named templates/*.md exists)"
}

check_agents_no_templates() {
  local f hit
  for f in "$AGENTS_DIR"/*.md; do
    [ -f "$f" ] || continue
    hit=$(grep -n 'templates/' "$f" || true)
    if [ -n "$hit" ]; then
      problem "$f mentions templates/ (line $(printf '%s\n' "$hit" | cut -d: -f1 | tr '\n' ' ' | sed 's/ $//'))"
    fi
  done
  finish_group "agents never mention templates/"
}

# --- Agent frontmatter ----------------------------------------------------------

check_agent_frontmatter() {
  local f base name is_ro has_tools tools t found=0 bash_ok a
  for f in "$AGENTS_DIR"/*.md; do
    [ -f "$f" ] || continue
    found=1
    base=${f##*/}
    base=${base%.md}
    name=$(fm_value "$f" name)
    if [ "$name" != "$base" ]; then
      problem "$f: frontmatter name is '$name', expected '$base'"
    fi

    is_ro=no
    [ "$(fm_value "$f" readonly)" = "true" ] && is_ro=yes
    has_tools=no
    fm_has "$f" tools && has_tools=yes
    if [ "$is_ro" = yes ] && [ "$has_tools" = no ]; then
      problem "$f: readonly: true without tools:"
    fi
    if [ "$is_ro" = no ] && [ "$has_tools" = yes ]; then
      problem "$f: tools: without readonly: true"
    fi

    tools=$(fm_tools "$f")
    bash_ok=no
    for a in $BASH_AGENTS; do
      [ "$a" = "$base" ] && bash_ok=yes
    done
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      if [ "$is_ro" = yes ] && { [ "$t" = Edit ] || [ "$t" = Write ]; }; then
        problem "$f: read-only agent has tool $t"
      fi
      if [ "$t" = Bash ] && [ "$bash_ok" = no ]; then
        problem "$f: only factory-reviewer and factory-verifier may have tool Bash"
      fi
    done <<EOF
$tools
EOF
  done
  [ "$found" -eq 1 ] || problem "no agents found under $AGENTS_DIR/"
  finish_group "agent frontmatter (name, readonly/tools, safe tools)"
}

# --- Stale paths ----------------------------------------------------------------

check_stale_paths() {
  local hits line
  hits=$(git grep -n -e '\.ai-factory/templates' -e '\.ai-factory/framework' -e '\.ai-factory/examples' -e 'sync\.sh' \
    -- . ':!scripts/check.sh' ':!scripts/test-*.sh' ':!.ai-factory/projects' ':!.ai-factory/archive' |
    grep -vF 'Generated by .ai-factory/sync.sh' || true)
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    # file:line: content
    problem "$(printf '%s\n' "$line" | sed 's/^\([^:]*:[0-9]*\):/\1: /')"
  done <<EOF
$hits
EOF
  finish_group "no retired paths in tracked files"
}

# --- Verifier contract ----------------------------------------------------------

check_verifier_contract() {
  local rows row label req cfg cfg_req label_list
  rows=$(table_rows "$VERIFIER" '| Check | Config label (Commands table) | Required |')
  cfg=$(config_rows)
  if [ -z "$rows" ]; then
    problem "$VERIFIER: no Checks table (header '| Check | Config label (Commands table) | Required |')"
  fi
  label_list=""
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    label=$(bold "$(cell "$row" 2)")
    req=$(cell "$row" 3)
    label_list="$label_list
$label"
    if ! printf '%s\n' "$cfg" | grep -q "^$label="; then
      problem "$VERIFIER: label **$label** is not a Commands label in $CONFIG_TEMPLATE"
      continue
    fi
    cfg_req=no
    printf '%s\n' "$cfg" | grep -qx "$label=Required" && cfg_req=yes
    if [ "$cfg_req" = yes ] && [ "$req" != Yes ]; then
      problem "$VERIFIER: **$label** is Required in $CONFIG_TEMPLATE but its Required column is '$req', expected 'Yes'"
    fi
    if [ "$cfg_req" = no ] && [ "$req" = Yes ]; then
      problem "$VERIFIER: **$label** is not Required in $CONFIG_TEMPLATE but its Required column is 'Yes'"
    fi
  done <<EOF
$rows
EOF
  while IFS= read -r row; do
    case "$row" in
    *=Required)
      label=${row%=Required}
      printf '%s\n' "$label_list" | grep -qxF "$label" ||
        problem "$VERIFIER: Required Commands label **$label** has no row in the Checks table"
      ;;
    esac
  done <<EOF
$cfg
EOF

  if ! grep -q '^## Verdict Rules' "$VERIFIER"; then
    problem "$VERIFIER: no '## Verdict Rules' section"
  elif ! awk '/^## Verdict Rules/ { s = 1; next } s && /^## / { exit } s { print }' "$VERIFIER" |
    grep -qi 'not configured'; then
    problem "$VERIFIER: the Verdict Rules section does not mention 'not configured'"
  fi

  while IFS= read -r row; do
    [ -n "$row" ] || continue
    problem "$VERIFIER:${row%%:*}: mentions skip without optional"
  done <<EOF
$(grep -ni 'skip' "$VERIFIER" | grep -vi 'optional' || true)
EOF
  finish_group "Verifier contract (labels, Required, verdict and skip wording)"
}

check_build_routing() {
  local row2
  row2=$(table_rows "$BUILD" '| Reviewer verdict' | sed -n '2p')
  case "$row2" in
  *"not configured"*) ;;
  *) problem "$BUILD: the second row of the Step C table does not contain 'not configured'" ;;
  esac
  grep -qF 'overrides every other row' "$BUILD" ||
    problem "$BUILD: the phrase 'overrides every other row' is missing"
  finish_group "factory-build Step C routes 'not configured' first"
}

check_frozen_labels() {
  local actual
  actual=$(config_rows | tr '\n' ',' | sed 's/,$//')
  if [ "$actual" != "$FROZEN_LABELS" ]; then
    problem "$CONFIG_TEMPLATE: Commands labels are '$actual', expected '$FROZEN_LABELS' (label=Required)"
  fi
  finish_group "frozen config Commands labels"
}

# --- Repository -----------------------------------------------------------------

check_installer_mode() {
  local entry mode
  entry=$(git ls-files -s -- install.sh)
  if [ -z "$entry" ]; then
    problem "install.sh is not tracked"
  else
    mode=${entry%% *}
    [ "$mode" = 100755 ] || problem "install.sh is tracked with mode $mode, expected 100755"
  fi
  finish_group "install.sh is tracked as executable"
}

check_tool_dirs() {
  local tracked p
  tracked=$(git ls-files -- .claude .cursor)
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    problem "tracked tool directory path: $p"
  done <<EOF
$tracked
EOF
  finish_group "no tracked .claude/ or .cursor/ paths"
}

check_skill_frontmatter
check_skill_templates
check_agents_no_templates
check_agent_frontmatter
check_stale_paths
check_verifier_contract
check_build_routing
check_frozen_labels
check_installer_mode
check_tool_dirs

if [ "$FAILED" -ne 0 ]; then
  echo "check.sh: FAILED"
  exit 1
fi
echo "check.sh: all $GROUPS_PASSED rule groups passed"
