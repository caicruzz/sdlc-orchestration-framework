#!/usr/bin/env bash
# T004 stage-skills test: factory-design, factory-plan and factory-archive use
# the templates that ship inside each skill and steer to factory-setup.
#
# Read-only. One function per scenario; each check prints "ok <check>" or
# "FAIL <check>". Exits non-zero if any check fails. Only lasting results are
# asserted here (file contents and exact phrases); facts about the change
# itself (which files the commit touched) are checked by the Reviewer.
#
# Backticks in single-quoted strings are literal Markdown, never expansions.
# shellcheck disable=SC2016
set -euo pipefail
cd "$(dirname "$0")/.."

FAILED=0

ok() { echo "ok   $*"; }
bad() {
  echo "FAIL $*"
  FAILED=1
}

# check <description> <command...>: run a test command, report ok/FAIL.
check() {
  local desc="$1"
  shift
  if "$@"; then ok "$desc"; else bad "$desc"; fi
}

DESIGN=plugin/skills/factory-design/SKILL.md
PLAN=plugin/skills/factory-plan/SKILL.md
ARCHIVE=plugin/skills/factory-archive/SKILL.md
REFERENCE=plugin/skills/factory-archive/reference.md

RULE='Templates are in `templates/` next to this SKILL.md. Paste the template'"'"'s full content into the subagent prompt under a `Template` heading'

# section <file> <heading>: print the body of the "## <heading>..." section
# (heading line excluded) up to the next "## " heading.
section() {
  awk -v h="## $2" '
    index($0, h) == 1 { on = 1; next }
    on && /^## / { exit }
    on { print }
  ' "$1" 2>/dev/null || true
}

# has <text> <fixed-string>: the text contains the string.
has() { printf '%s\n' "$1" | grep -qF -- "$2"; }
# lacks <text> <fixed-string>: the text does not contain the string.
lacks() { ! has "$1" "$2"; }
# file_has / file_lacks <file> <fixed-string>
file_has() { grep -qF -- "$2" "$1" 2>/dev/null; }
file_lacks() { [ -f "$1" ] && ! grep -qF -- "$2" "$1"; }
# lacks_re <text> <extended-regex>
lacks_re() { ! printf '%s\n' "$1" | grep -qE -- "$2"; }

# Scenario: Path A pastes the Design Doc template into the Architect prompt
scenario_design_path_a_pastes_template() {
  echo "# Path A pastes the Design Doc template into the Architect prompt"
  local body
  body=$(section "$DESIGN" "Path A")
  check "Path A names templates/design.md" has "$body" 'templates/design.md'
  check "Path A says it is next to this SKILL.md" has "$body" 'next to this SKILL.md'
  check "Path A says to paste the full content" has "$body" 'full content'
  check "Path A pastes under a Template heading" has "$body" 'under a **`Template`** heading'
  check "Path A passes the feature request" has "$body" 'feature request'
  check "Path A passes the output path" has "$body" '`.ai-factory/projects/<slug>/00-design.md`'
  check "Path A invokes factory-architect" has "$body" 'factory-architect'
  check "Path A no longer says the Architect reads design.md" \
    lacks_re "$body" 'reads[^.]*design\.md'
  check "Path A no longer names .ai-factory/templates" lacks "$body" '.ai-factory/templates'
}

# Scenario: The evaluation is shaped with the skill's template when persisted
scenario_design_evaluation_shaped_with_template() {
  echo "# The evaluation is shaped with the skill's template when persisted"
  local body
  body=$(section "$DESIGN" "Both paths")
  check "Evaluator section names templates/evaluation.md" has "$body" 'templates/evaluation.md'
  check "Evaluator section says it is next to this SKILL.md" has "$body" 'next to this SKILL.md'
  check "Evaluator section shapes the report when persisting" \
    has "$body" 'shape the returned report with it when persisting'
  check "Evaluator section persists to evaluations/00-design-evaluation.md" \
    has "$body" '.ai-factory/projects/<slug>/evaluations/00-design-evaluation.md'
  check "Evaluator prompt includes no template" has "$body" 'includes **no template**'
  check "Evaluator prompt is only the Design Doc path" has "$body" 'only the Design Doc path'
}

# Scenario: Template rule sentence
scenario_design_template_rule_sentence() {
  echo "# Template rule sentence (factory-design)"
  check "factory-design states the template rule" file_has "$DESIGN" "$RULE"
  check "factory-design says to shape the evaluation report when persisting" \
    file_has "$DESIGN" 'shape the returned report with it when persisting'
}

# Scenario: Design stage offers setup when config is missing
scenario_design_offers_setup() {
  echo "# Design stage offers setup when config is missing"
  local body
  body=$(section "$DESIGN" "Preconditions")
  check "design preconditions name .ai-factory/config.md" has "$body" '.ai-factory/config.md'
  check "design preconditions cover a missing config" has "$body" 'is missing'
  check "design preconditions offer to run factory-setup first" \
    has "$body" 'offer to run `factory-setup` first'
}

# Scenario: Quick reference points at the bundled templates
scenario_design_quick_reference() {
  echo "# Quick reference points at the bundled templates"
  local body pre3
  body=$(section "$DESIGN" "Quick reference")
  check "Quick reference Design Doc template row reads templates/design.md" \
    has "$body" '| Design Doc template | `templates/design.md` (next to this SKILL.md) |'
  check "Quick reference has a templates/evaluation.md row" \
    has "$body" '`templates/evaluation.md` (next to this SKILL.md)'
  pre3=$(section "$DESIGN" "Preconditions" | grep '^3\. ' || true)
  check "precondition 3 points at templates/design.md" has "$pre3" 'templates/design.md'
  check "precondition 3 says next to this SKILL.md" has "$pre3" 'next to this SKILL.md'
  check "factory-design has no .ai-factory/templates" file_lacks "$DESIGN" '.ai-factory/templates'
  check "plugin/skills/factory-design/templates/design.md exists" \
    test -f plugin/skills/factory-design/templates/design.md
  check "plugin/skills/factory-design/templates/evaluation.md exists" \
    test -f plugin/skills/factory-design/templates/evaluation.md
}

# Scenario: The Planner prompt carries both templates
scenario_plan_planner_prompt_carries_templates() {
  echo "# The Planner prompt carries both templates"
  local body qr
  body=$(section "$PLAN" "Procedure")
  check "Procedure names templates/epic.md" has "$body" 'templates/epic.md'
  check "Procedure names templates/task.md" has "$body" 'templates/task.md'
  check "Procedure says next to this SKILL.md" has "$body" 'next to this SKILL.md'
  check "Procedure pastes both full contents" has "$body" 'full content of **both**'
  check "Procedure pastes under a Template heading" has "$body" 'under a **`Template`** heading'
  check "Procedure passes the Design Doc path" has "$body" '.ai-factory/projects/<slug>/00-design.md'
  check "Procedure invokes factory-planner" has "$body" 'factory-planner'
  qr=$(section "$PLAN" "Quick reference")
  check "Quick reference epic row reads templates/epic.md" \
    has "$qr" '| Epic template | `templates/epic.md` (next to this SKILL.md) |'
  check "Quick reference task row reads templates/task.md" \
    has "$qr" '| Task template | `templates/task.md` (next to this SKILL.md) |'
  check "factory-plan states the template rule" file_has "$PLAN" "$RULE"
  check "factory-plan has no .ai-factory/templates" file_lacks "$PLAN" '.ai-factory/templates'
  check "plugin/skills/factory-plan/templates/epic.md exists" \
    test -f plugin/skills/factory-plan/templates/epic.md
  check "plugin/skills/factory-plan/templates/task.md exists" \
    test -f plugin/skills/factory-plan/templates/task.md
}

# Scenario: Plan stage offers setup when config is missing
scenario_plan_offers_setup() {
  echo "# Plan stage offers setup when config is missing"
  local body
  body=$(section "$PLAN" "Preconditions")
  check "plan preconditions name .ai-factory/config.md" has "$body" '.ai-factory/config.md'
  check "plan preconditions cover a missing config" has "$body" 'is missing'
  check "plan preconditions offer to run factory-setup first" \
    has "$body" 'offer to run `factory-setup` first'
}

# invoking_section <file>: print the "## Invoking subagents" section, heading
# included, up to the next "## " heading, with trailing blank lines dropped.
invoking_section() {
  awk '
    $0 == "## Invoking subagents" { on = 1; print; next }
    on && /^## / { exit }
    on {
      if ($0 == "") { blanks++ ; next }
      while (blanks > 0) { print ""; blanks-- }
      print
    }
  ' "$1" 2>/dev/null || true
}

# expected_invoking_section: print the exact "Invoking subagents" contract.
# (A top-level function, not a heredoc inside $(...): bash 3.2 mis-parses
# quotes in a heredoc nested in command substitution.)
expected_invoking_section() {
  cat <<'EOF'
## Invoking subagents
Wherever this skill says *invoke the `factory-<name>` subagent*:
- **Cursor**: delegate by name, e.g. `/factory-<name> <input>`.
- **Claude Code**: call the Agent tool with `subagent_type: factory-<name>`.
The installed agents live in `~/.claude/agents/`; a project `.claude/agents/factory-<name>.md`
overrides one by each tool's own precedence. Pass only the inputs this skill names
(paths, task IDs, inlined template content).
EOF
}

# Scenario: Invoking subagents section is replaced in factory-design and factory-plan
scenario_invoking_subagents_section() {
  echo "# Invoking subagents section is replaced in factory-design and factory-plan"
  local expected actual f
  expected=$(expected_invoking_section)
  for f in "$DESIGN" "$PLAN"; do
    actual=$(invoking_section "$f")
    if [ "$actual" = "$expected" ]; then
      ok "$f Invoking subagents section matches the contract exactly"
    else
      bad "$f Invoking subagents section matches the contract exactly"
      diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed 's/^/     /' || true
    fi
    check "$f mentions no sync.sh" file_lacks "$f" 'sync.sh'
    check "$f mentions no .ai-factory/framework" file_lacks "$f" '.ai-factory/framework'
  done
}

# Scenario: factory-archive gets no subagent section
scenario_archive_no_subagent_section() {
  echo "# factory-archive gets no subagent section"
  check "$ARCHIVE exists" test -f "$ARCHIVE"
  check "factory-archive has no Invoking subagents section" \
    file_lacks "$ARCHIVE" 'Invoking subagents'
}

# Scenario: Template rules are removed
scenario_archive_template_rules_removed() {
  echo "# Template rules are removed (factory-archive)"
  check "factory-archive has no .ai-factory/templates" file_lacks "$ARCHIVE" '.ai-factory/templates'
  check "factory-archive has no 'framework templates are out of scope'" \
    file_lacks "$ARCHIVE" 'framework templates are out of scope'
  check "Verification keeps '00-design.md was moved, not edited'" \
    file_has "$ARCHIVE" '**`00-design.md`** was moved, not edited'
}

# Scenario: Examples rules are removed
scenario_archive_examples_rules_removed() {
  echo "# Examples rules are removed (factory-archive)"
  check "factory-archive has no .ai-factory/examples" file_lacks "$ARCHIVE" '.ai-factory/examples'
  check "factory-archive has no custom-projectRoot examples edge case" \
    file_lacks "$ARCHIVE" 'explicitly** set a custom `projectRoot`'
}

# Scenario: The archive reference no longer cites framework paths
scenario_reference_no_framework_paths() {
  echo "# The archive reference no longer cites framework paths"
  local intro graph
  intro=$(grep -F 'illustrative OAuth2 example' "$REFERENCE" 2>/dev/null || true)
  check "reference describes the fragments as an illustrative OAuth2 example" \
    test -n "$intro"
  if [ -n "$intro" ] && lacks "$intro" 'examples/'; then
    ok "the illustrative OAuth2 example line names no examples/ path"
  else
    bad "the illustrative OAuth2 example line names no examples/ path"
  fi
  graph=$(grep -F '### Legend' "$REFERENCE" 2>/dev/null || true)
  check "the graph section is copied from the project's own 01-epic.md" \
    has "$graph" 'copied as it appears in the project'"'"'s own `01-epic.md`'
  check "reference has no .ai-factory/templates" file_lacks "$REFERENCE" '.ai-factory/templates'
  check "reference has no .ai-factory/examples" file_lacks "$REFERENCE" '.ai-factory/examples'
}

scenario_design_path_a_pastes_template
scenario_design_evaluation_shaped_with_template
scenario_design_template_rule_sentence
scenario_design_offers_setup
scenario_design_quick_reference
scenario_plan_planner_prompt_carries_templates
scenario_plan_offers_setup
scenario_invoking_subagents_section
scenario_archive_no_subagent_section
scenario_archive_template_rules_removed
scenario_archive_examples_rules_removed
scenario_reference_no_framework_paths

if [ "$FAILED" -ne 0 ]; then
  echo "test-stage-skills: FAILED"
  exit 1
fi
echo "test-stage-skills: all checks passed"
