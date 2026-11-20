#!/usr/bin/env bash
# T002 agent contract test: agent frontmatter works in both Claude Code and
# Cursor, and no agent reads a template file from disk.
#
# Read-only. One function per scenario; each check prints "ok <check>" or
# "FAIL <check>". Exits non-zero if any check fails. Only lasting results are
# asserted here (file contents, frontmatter, exact phrases); facts about the
# change itself (unchanged bodies, untouched Coder and Verifier files) are
# checked by the Reviewer.
set -euo pipefail
cd "$(dirname "$0")/.."

FAILED=0
AGENTS_DIR=plugin/agents

ok() { echo "ok   $*"; }
bad() {
  echo "FAIL $*"
  FAILED=1
}

# frontmatter <file>: print the lines between the first and second "---".
frontmatter() {
  awk 'NR == 1 && $0 == "---" { inside = 1; next }
       inside && $0 == "---" { exit }
       inside { print }' "$1" 2>/dev/null || true
}

# top_keys <file>: print the frontmatter's top-level keys, in order, one per
# line (continuation lines of folded values are skipped).
top_keys() {
  frontmatter "$1" | sed -n 's/^\([A-Za-z_][A-Za-z0-9_-]*\):.*/\1/p'
}

# section <file> <heading>: print the body of the "## <heading>" section (up
# to the next "## " heading) flattened to one line with single spaces.
section() {
  awk -v h="## $2" '$0 == h { inside = 1; next }
       inside && /^## / { exit }
       inside { print }' "$1" 2>/dev/null | tr '\n' ' ' | tr -s ' ' || true
}

# flat <file>: print the whole file flattened to one line with single spaces.
flat() {
  { tr '\n' ' ' <"$1"; } 2>/dev/null | tr -s ' ' || true
}

# has_key <file> <key>: the frontmatter has a top-level <key>.
has_key() { top_keys "$1" | grep -qxF "$2"; }

# key_line <file> <line>: the frontmatter contains exactly this line.
key_line() { frontmatter "$1" | grep -qxF -- "$2"; }

# contains <text> <needle>: fixed-string match.
contains() { printf '%s\n' "$1" | grep -qF -- "$2"; }

# check_contains <description> <text> <needle>
check_contains() {
  if contains "$2" "$3"; then ok "$1"; else bad "$1"; fi
}

# check_no_template_paths <file>
check_no_template_paths() {
  local f="$1"
  if [ ! -f "$f" ]; then
    bad "$f exists"
    return 0
  fi
  if grep -qsF '.ai-factory/templates' "$f"; then
    bad "$f does not mention .ai-factory/templates"
  else
    ok "$f does not mention .ai-factory/templates"
  fi
  if grep -qsF 'templates/' "$f"; then
    bad "$f does not contain the string templates/"
  else
    ok "$f does not contain the string templates/"
  fi
}

# check_key_order <file> <expected keys, space separated>
check_key_order() {
  local f="$1" want="$2" got
  got=$(top_keys "$f" | tr '\n' ' ' | sed 's/ $//')
  if [ "$got" = "$want" ]; then
    ok "$f frontmatter keys are: $want"
  else
    bad "$f frontmatter keys are: $want (found: $got)"
  fi
}

# Scenario: The Evaluator is read-only in both tools
scenario_evaluator_read_only() {
  echo "# The Evaluator is read-only in both tools"
  local f="$AGENTS_DIR/factory-evaluator.md"
  if key_line "$f" "readonly: true"; then ok "$f has readonly: true"; else bad "$f has readonly: true"; fi
  if key_line "$f" "tools: Read, Grep, Glob"; then
    ok "$f has tools: Read, Grep, Glob"
  else
    bad "$f has tools: Read, Grep, Glob"
  fi
  if has_key "$f" shell; then bad "$f has no shell: key"; else ok "$f has no shell: key"; fi
  check_key_order "$f" "name description model readonly tools"
}

# Scenario: The Reviewer is read-only but can run commands
scenario_reviewer_read_only_with_shell() {
  echo "# The Reviewer is read-only but can run commands"
  local f="$AGENTS_DIR/factory-reviewer.md"
  if key_line "$f" "readonly: true"; then ok "$f has readonly: true"; else bad "$f has readonly: true"; fi
  if key_line "$f" "tools: Read, Grep, Glob, Bash"; then
    ok "$f has tools: Read, Grep, Glob, Bash"
  else
    bad "$f has tools: Read, Grep, Glob, Bash"
  fi
  if has_key "$f" shell; then bad "$f has no shell: key"; else ok "$f has no shell: key"; fi
  check_key_order "$f" "name description model readonly tools"
}

# Scenario: Writable agents carry neither form
scenario_writable_agents_carry_neither_form() {
  echo "# Writable agents carry neither form"
  local a f k
  for a in factory-architect factory-planner factory-coder; do
    f="$AGENTS_DIR/$a.md"
    if [ -z "$(frontmatter "$f")" ]; then
      bad "$f has frontmatter"
      continue
    fi
    for k in readonly tools shell; do
      if has_key "$f" "$k"; then bad "$f has no $k: key"; else ok "$f has no $k: key"; fi
    done
  done
}

# Scenario: Architect invoked with a template
scenario_architect_with_template() {
  echo "# Architect invoked with a template"
  local f="$AGENTS_DIR/factory-architect.md" text phrase
  text=$(flat "$f")
  # shellcheck disable=SC2016 # backticks are literal Markdown
  check_contains "$f says the template comes under a Template heading" "$text" 'under a **`Template`** heading'
  check_contains "$f names the output path" "$text" '.ai-factory/projects/<slug>/00-design.md'
  check_contains "$f writes the Design Doc by starting from the template in its prompt" "$text" \
    'by **starting from the template in your prompt** and preserving its structure'
  for phrase in \
    'same heading hierarchy' \
    '**Metadata** table shape' \
    '**File Impact Map**' \
    '**Risks & Mitigations**' \
    '**Approval**' \
    'placeholders replaced with real content'; do
    check_contains "$f preserves the template's $phrase" "$text" "$phrase"
  done
  for phrase in \
    '**Problem Statement**' '**Goals**' '**Architecture Overview**' \
    '**Data Model Changes**' '**API Surface Changes**' '**Open Questions**'; do
    check_contains "$f keeps the substance bullet $phrase" "$text" "$phrase"
  done
}

# Scenario: Architect invoked without a template
scenario_architect_without_template() {
  echo "# Architect invoked without a template"
  local f="$AGENTS_DIR/factory-architect.md" text
  text=$(flat "$f")
  # shellcheck disable=SC2016 # backticks are literal Markdown
  check_contains "$f stops when its prompt has no Template section" "$text" \
    'If your prompt contains no `Template` section, write nothing and reply:'
  # shellcheck disable=SC2016 # backticks are literal Markdown
  check_contains "$f replies with the factory-design pointer" "$text" \
    '"No Design Doc template in my prompt; run the `factory-design` skill, which supplies it."'
}

# Scenario: The Architect never reads a template file
scenario_architect_never_reads_template_file() {
  echo "# The Architect never reads a template file"
  local f="$AGENTS_DIR/factory-architect.md"
  check_no_template_paths "$f"
  # shellcheck disable=SC2016 # backticks are literal Markdown
  if [ ! -f "$f" ] || grep -qsF '`design.md`' "$f"; then
    bad "$f does not refer to design.md"
  else
    ok "$f does not refer to design.md"
  fi
  if grep -qsxF -- '- **Do not omit** Metadata, Non-Goals, Approval, or any table scaffolding present in **the template in your prompt**' "$f"; then
    ok "$f Rules bullet says the template in the prompt"
  else
    bad "$f Rules bullet says the template in the prompt"
  fi
}

# Scenario: Planner invoked with both templates
scenario_planner_with_templates() {
  echo "# Planner invoked with both templates"
  local f="$AGENTS_DIR/factory-planner.md" input output
  input=$(section "$f" Input)
  output=$(section "$f" Output)
  check_contains "$f Input names the Design Doc path" "$input" '.ai-factory/projects/<slug>/00-design.md'
  # shellcheck disable=SC2016 # backticks are literal Markdown
  check_contains "$f Input names the Template heading" "$input" 'Under a **`Template`** heading'
  check_contains "$f Input names the full epic and task templates" "$input" \
    'the full epic template and the full task template'
  # shellcheck disable=SC2016 # backticks are literal Markdown
  check_contains "$f Output: 01-epic.md follows the epic template in its prompt" "$output" \
    '`01-epic.md` — Overview of the full scope, following the epic template in your prompt'
  # shellcheck disable=SC2016 # backticks are literal Markdown
  check_contains "$f Output: each task file follows the task template in its prompt" "$output" \
    '`tasks/T001-<slug>.md` — One file per task, following the task template in your prompt'
}

# Scenario: Planner invoked without the templates
scenario_planner_without_templates() {
  echo "# Planner invoked without the templates"
  local f="$AGENTS_DIR/factory-planner.md" text
  text=$(flat "$f")
  check_contains "$f stops when its prompt lacks a template" "$text" \
    'If your prompt lacks the epic template or the task template, write nothing and reply:'
  # shellcheck disable=SC2016 # backticks are literal Markdown
  check_contains "$f replies with the factory-plan pointer" "$text" \
    '"No epic/task template in my prompt; run the `factory-plan` skill, which supplies them."'
}

# Scenario: The Planner never reads a template file
scenario_planner_never_reads_template_file() {
  echo "# The Planner never reads a template file"
  local f="$AGENTS_DIR/factory-planner.md" heading
  check_no_template_paths "$f"
  # shellcheck disable=SC2016 # backticks are literal Markdown
  if grep -qsF -- '- [ ] `01-epic.md` follows the epic template in the prompt and includes **`## Task dependency graph`**' "$f"; then
    ok "$f epic checklist item names the epic template in the prompt"
  else
    bad "$f epic checklist item names the epic template in the prompt"
  fi
  # shellcheck disable=SC2016 # backticks are literal Markdown
  for heading in '### Epic file (`01-epic.md`)' '## Task Writing Rules' '## Quality Checklist'; do
    if grep -qsxF -- "$heading" "$f"; then ok "$f keeps $heading"; else bad "$f keeps $heading"; fi
  done
  if grep -qsF '**Diagram rules**' "$f"; then ok "$f keeps the diagram rules"; else bad "$f keeps the diagram rules"; fi
}

EXPECTED_REVIEWER_TAIL=$(
  cat <<'EOF'
## Verdict Rules

- **Pass** — All scenarios satisfied, no critical or high severity findings
- **Revisions-needed** — Any scenario not satisfied, or critical/high findings
  that could cause bugs, security issues, or performance problems

## Important

- You are ADVISORY. You suggest, you do not mandate
- The Coder has final say on whether to incorporate your feedback
- Focus on correctness and scenario coverage, not stylistic preferences
- Do NOT rewrite the code in your review — describe the issue and suggested fix
- Low-severity style nits should not block a pass verdict
EOF
)

# Scenario: Reviewer output floor replaces the template reference
scenario_reviewer_output_floor() {
  echo "# Reviewer output floor replaces the template reference"
  local f="$AGENTS_DIR/factory-reviewer.md" output phrase tail
  output=$(section "$f" Output)
  # shellcheck disable=SC2016 # backticks are literal Markdown
  for phrase in \
    'the task ID and title' \
    'for every Gherkin scenario in the task: its name, its status (`satisfied`, `partially-satisfied` or `not-satisfied`) and the evidence' \
    'each with a title, severity (`critical`, `high`, `medium` or `low`), location (`file:line`), description and suggested fix (described, not rewritten code)' \
    'notes on scenario coverage, assertion quality, isolation and mocks' \
    'a 2–3 sentence overall assessment' \
    '`pass` or `revisions-needed`, with the reasoning, followed by a one-line key-findings summary'; do
    check_contains "$f Output requires: $phrase" "$output" "$phrase"
  done
  check_contains "$f Output says it is read-only" "$output" 'You are read-only: do **not** write or edit any file.'
  # shellcheck disable=SC2016 # backticks are literal Markdown
  check_contains "$f Output says the orchestrating agent saves the report" "$output" \
    'The orchestrating agent saves it to `.ai-factory/projects/<slug>/reviews/T<id>-review.md` and updates the task file'
  check_no_template_paths "$f"
  tail=$(sed -n '/^## Verdict Rules$/,$p' "$f" 2>/dev/null || true)
  if [ "$tail" = "$EXPECTED_REVIEWER_TAIL" ]; then
    ok "$f Verdict Rules and Important sections are as specified"
  else
    bad "$f Verdict Rules and Important sections are as specified"
  fi
}

# Scenario: The Verifier is left for its own task
# (That factory-verifier.md is unchanged by this task is a fact about the
# change; the Reviewer checks it. Here: the file is still in place.)
scenario_verifier_left_alone() {
  echo "# The Verifier is left for its own task"
  if [ -f "$AGENTS_DIR/factory-verifier.md" ]; then
    ok "$AGENTS_DIR/factory-verifier.md exists"
  else
    bad "$AGENTS_DIR/factory-verifier.md exists"
  fi
}

scenario_evaluator_read_only
scenario_reviewer_read_only_with_shell
scenario_writable_agents_carry_neither_form
scenario_architect_with_template
scenario_architect_without_template
scenario_architect_never_reads_template_file
scenario_planner_with_templates
scenario_planner_without_templates
scenario_planner_never_reads_template_file
scenario_reviewer_output_floor
scenario_verifier_left_alone

if [ "$FAILED" -ne 0 ]; then
  echo "test-agent-contracts: FAILED"
  exit 1
fi
echo "test-agent-contracts: all checks passed"
