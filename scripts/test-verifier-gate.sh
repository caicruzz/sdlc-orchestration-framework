#!/usr/bin/env bash
# shellcheck disable=SC2016 # backticks and $ in single quotes are literal Markdown
# T003 test: the Verifier fails unconfigured Required checks and factory-build
# routes them to the human.
#
# Read-only. One function per scenario; each check prints "ok <check>" or
# "FAIL <check>". Exits non-zero if any check fails. Behavioural scenarios
# (placeholder, none, missing row) are verified by reading the instructions
# that produce that behaviour. Only lasting results are asserted here (file
# contents); facts about the change itself are checked by the Reviewer.
set -euo pipefail
cd "$(dirname "$0")/.."

VERIFIER=plugin/agents/factory-verifier.md
BUILD=plugin/skills/factory-build/SKILL.md
CONFIG_TEMPLATE=plugin/skills/factory-setup/templates/config.md

FAILED=0

ok() { echo "ok   $*"; }
bad() {
  echo "FAIL $*"
  FAILED=1
}

# has <file> <text>: the file contains the fixed text.
has() {
  local desc="$1 contains: $2"
  if grep -qF -- "$2" "$1" 2>/dev/null; then ok "$desc"; else bad "$desc"; fi
}

# lacks <file> <text>: the file does not contain the fixed text.
lacks() {
  local desc="$1 does not contain: $2"
  if grep -qF -- "$2" "$1" 2>/dev/null; then bad "$desc"; else ok "$desc"; fi
}

# same <description> <expected> <actual>
same() {
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    bad "$1"
    printf '  expected:\n%s\n  found:\n%s\n' "$2" "$3"
  fi
}

# table_after <file> <heading>: print the first Markdown table after the
# heading line (lines starting with "|"), stopping at the first non-table line.
table_after() {
  awk -v h="$2" '
    $0 == h { found = 1; next }
    found && /^\|/ { intable = 1; print; next }
    found && intable { exit }
  ' "$1"
}

# frontmatter <file>: print the lines between the first two "---" lines.
frontmatter() {
  awk 'NR == 1 && $0 == "---" { infm = 1; next } infm && $0 == "---" { exit } infm { print }' "$1"
}

# section <file> <heading>: print the section body up to the next "## " heading.
section() {
  awk -v h="$2" '
    $0 == h { found = 1; next }
    found && /^## / { exit }
    found { print }
  ' "$1"
}

# Scenario: Checks are keyed by Commands-table labels
scenario_checks_keyed_by_labels() {
  echo "# Checks are keyed by Commands-table labels"
  local expected actual key label
  expected='| Check | Config label (Commands table) | Required |
|---|---|---|
| Tests | **Test** | Yes |
| Lint | **Lint** | Yes |
| Type check | **Type check** | No |
| Build | **Build** | No |'
  actual=$(table_after "$VERIFIER" "## Checks to Run")
  same "Verifier Checks table is exactly the four labelled rows" "$expected" "$actual"
  for key in test_command lint_command typecheck_command build_command; do
    lacks "$VERIFIER" "$key"
  done
  # Labels are a subset of the config template's Commands labels.
  for label in Test Lint "Type check" Build; do
    if table_after "$CONFIG_TEMPLATE" "## Commands" | grep -qF "| **$label** |"; then
      ok "config template Commands table has **$label**"
    else
      bad "config template Commands table has **$label**"
    fi
  done
  if section "$VERIFIER" "## Process" | grep -F '**Commands** table' | grep -qF 'bold labels'; then
    ok "Process step finds Commands rows by their bold labels"
  else
    bad "Process step finds Commands rows by their bold labels"
  fi
}

# Scenario: Required check with a placeholder value
scenario_required_placeholder() {
  echo "# Required check with a placeholder value"
  has "$VERIFIER" 'A row is *not configured* when it is missing, empty, `none`, or only an HTML-comment placeholder.'
  has "$VERIFIER" 'A Required check (Tests, Lint) that is not configured is `fail`. Do not run anything for it'
  has "$VERIFIER" '"not configured: set **Lint** in `.ai-factory/config.md` (human action required)"'
  has "$VERIFIER" '**or any Required check is not configured**'
}

# Scenario: Required check set to `none`
scenario_required_none() {
  echo "# Required check set to none"
  has "$VERIFIER" 'missing, empty, `none`, or only'
  has "$VERIFIER" '"not configured: set **<label>** in `.ai-factory/config.md` (human action required)"'
  # Test maps to Tests and is Required.
  has "$VERIFIER" '| Tests | **Test** | Yes |'
}

# Scenario: Required row missing or empty
scenario_required_missing_or_empty() {
  echo "# Required row missing or empty"
  has "$VERIFIER" 'when it is missing, empty,'
  has "$VERIFIER" 'Verdict Rules'
  if section "$VERIFIER" "## Verdict Rules" | grep -qF 'not configured'; then
    ok "Verdict Rules mention not configured"
  else
    bad "Verdict Rules mention not configured"
  fi
}

# Scenario: Optional check not configured
scenario_optional_not_configured() {
  echo "# Optional check not configured"
  has "$VERIFIER" 'An optional check (Type check, Build) that is not configured is `skipped`. Do not run anything for it, and it does not affect the verdict.'
  has "$VERIFIER" '| Type check | **Type check** | No |'
  has "$VERIFIER" '| Build | **Build** | No |'
}

# Scenario: Install and Format are never run
scenario_install_format_never_run() {
  echo "# Install and Format are never run"
  has "$VERIFIER" 'Never run the **Install** or **Format** rows, and never report them as checks.'
  if table_after "$VERIFIER" "## Checks to Run" | grep -qE 'Install|Format'; then
    bad "Checks table has no Install or Format row"
  else
    ok "Checks table has no Install or Format row"
  fi
}

# Scenario: Every configured check passes
scenario_all_configured_pass() {
  echo "# Every configured check passes"
  has "$VERIFIER" '**Pass**: every Required check is configured and every configured check exits 0.'
}

# Scenario: A configured check exits non-zero
scenario_configured_check_fails() {
  echo "# A configured check exits non-zero"
  has "$VERIFIER" '**Fail**: any check exits non-zero'
  has "$VERIFIER" '`fail` when it exits non-zero'
  has "$VERIFIER" 'the exit code (or "—" when not run)'
  has "$VERIFIER" 'the failure details on failure'
}

# Scenario: Verdict Rules and the Important bullet
scenario_wording_contract() {
  echo "# Verdict Rules and the Important bullet"
  has "$VERIFIER" '**Pass**: every Required check is configured and every configured check exits 0. **Fail**: any check exits non-zero, **or any Required check is not configured**.'
  has "$VERIFIER" '- An optional check that is not configured is `skipped`; a Required check that is not configured is `fail` (not configured).'
  has "$VERIFIER" 'A row is *not configured* when it is missing, empty, `none`, or only an HTML-comment placeholder.'
  lacks "$VERIFIER" 'ALL checks exit with code 0'
  lacks "$VERIFIER" 'If a check command is missing from config'
}

# Scenario: No unconditional skip rule remains
scenario_no_unconditional_skip() {
  echo "# No unconditional skip rule remains"
  local stray
  stray=$(grep -in 'skip' "$VERIFIER" | grep -vi 'optional' || true)
  if [ -z "$stray" ]; then
    ok "every Verifier line mentioning skip also says optional"
  else
    bad "every Verifier line mentioning skip also says optional"
    printf '%s\n' "$stray"
  fi
  lacks "$VERIFIER" 'If a config key is empty or marked `none`, skip that check.'
}

# Scenario: Verifier output floor replaces the template reference
scenario_output_floor() {
  echo "# Verifier output floor replaces the template reference"
  local out field
  out=$(section "$VERIFIER" "## Output")
  for field in \
    'The task ID, when one was given' \
    'For each of Tests, Lint, Type check and Build:' \
    'the label' \
    'the command that was run (or "not run")' \
    'the status: `pass`, `fail`, or — for an optional check that is not configured — `skipped`' \
    'the exit code (or "—" when not run)' \
    'an output excerpt: the summary line on success, the failure details on failure, the not-configured message when not configured' \
    'The verdict (`pass` or `fail`)' \
    'The failing checks (or "none")'; do
    if printf '%s\n' "$out" | grep -qF -- "$field"; then
      ok "Output lists: $field"
    else
      bad "Output lists: $field"
    fi
  done
  lacks "$VERIFIER" '.ai-factory/templates'
  lacks "$VERIFIER" 'templates/'
  has "$VERIFIER" '.ai-factory/projects/<slug>/verifications/T<id>-verify.md'
}

# Scenario: Verifier frontmatter declares both tools' forms
scenario_frontmatter() {
  echo "# Verifier frontmatter declares both tools' forms"
  local fm
  fm=$(frontmatter "$VERIFIER")
  if printf '%s\n' "$fm" | grep -qx 'readonly: true'; then ok "frontmatter has readonly: true"; else bad "frontmatter has readonly: true"; fi
  if printf '%s\n' "$fm" | grep -qx 'tools: Read, Grep, Glob, Bash'; then
    ok "frontmatter has tools: Read, Grep, Glob, Bash"
  else
    bad "frontmatter has tools: Read, Grep, Glob, Bash"
  fi
  if printf '%s\n' "$fm" | grep -q '^shell:'; then bad "frontmatter has no shell: key"; else ok "frontmatter has no shell: key"; fi
}

# Scenario: Precondition requires Test and Lint
scenario_precondition() {
  echo "# Precondition requires Test and Lint"
  local line
  line=$(grep -E '^3\. ' "$BUILD" | head -n 1 || true)
  case "$line" in
    *'`.ai-factory/config.md` present **with Test and Lint filled**; otherwise stop and ask the human (suggest re-running `factory-setup`).'*)
      ok "precondition 3 requires Test and Lint filled" ;;
    *) bad "precondition 3 requires Test and Lint filled (found: $line)" ;;
  esac
  case "$line" in
    *'config only'*) ok "precondition 3 notes the Verifier uses config only" ;;
    *) bad "precondition 3 notes the Verifier uses config only" ;;
  esac
}

# step_c_row <n>: print the n-th data row of the Step C table.
step_c_row() {
  table_after "$BUILD" "### Step C — Reconcile outcomes" | sed -n "$(($1 + 2))p"
}

# Scenario: Step C routes a not-configured failure to the human
scenario_step_c_routes_to_human() {
  echo "# Step C routes a not-configured failure to the human"
  local expected rows after
  expected='| anything | **fail**, and a failed check is *not configured* | **Stop and ask the human to fill the command; do not append to the task file or re-invoke the Coder.** |'
  same "Step C second data row routes not configured to the human" "$expected" "$(step_c_row 2)"
  case "$(step_c_row 2)" in
    *'not configured'*) ok "Step C second data row contains not configured" ;;
    *) bad "Step C second data row contains not configured" ;;
  esac
  same "Step C first data row is pass | pass" '| pass | pass | Proceed to Step D |' "$(step_c_row 1)"
  rows=$(table_after "$BUILD" "### Step C — Reconcile outcomes" | sed -n '5,$p')
  same "Step C keeps the other rows" '| **revisions-needed** | anything | **Append** feedback to the task file (**do not** delete earlier feedback blobs), return to Step A |
| anything | **fail** | **Append** Verifier output to the task file, return to Step A |
| Mixed failure | Mixed failure | Append **both**, return to Step A |' "$rows"
  # The first non-blank line directly under the table.
  after=$(awk '
    $0 == "### Step C — Reconcile outcomes" { found = 1; next }
    found && /^\|/ { intable = 1; next }
    found && intable && NF { print; exit }
  ' "$BUILD")
  case "$after" in
    *'overrides every other row'*) ok "sentence under the Step C table says overrides every other row" ;;
    *) bad "sentence under the Step C table says overrides every other row (found: $after)" ;;
  esac
}

# Scenario: Reviewer wants revisions while a Required command is missing
scenario_revisions_and_missing_command() {
  echo "# Reviewer wants revisions while a Required command is missing"
  has "$BUILD" 'if any failed Verifier check is *not configured*, stop and ask the human even when the Reviewer also asked for revisions.'
  has "$BUILD" '| **Re-invoke the Coder** for a Verifier check that is *not configured* | Only a human can fill config commands; stop and ask the human |'
  has "$BUILD" 'nothing was appended to the task file and the Coder was **not** re-invoked'
}

# Scenario: Project override notice at loop start
scenario_project_override_notice() {
  echo "# Project override notice at loop start"
  local name
  has "$BUILD" 'using project override <path>'
  has "$BUILD" '.claude/agents/factory-<name>.md'
  has "$BUILD" '.cursor/agents/factory-<name>.md'
  for name in factory-coder factory-reviewer factory-verifier; do
    if section "$BUILD" "## Project overrides (at loop start)" | grep -qF "\`$name\`"; then
      ok "override notice checks $name"
    else
      bad "override notice checks $name"
    fi
  done
  if awk '/^## Project overrides/ { p = NR } /^## Loop \(one task iteration\)/ { l = NR } END { exit !(p && l && p < l) }' "$BUILD"; then
    ok "override notice comes before the loop"
  else
    bad "override notice comes before the loop"
  fi
}

# Scenario: Reports are shaped with the skill's own templates
scenario_skill_templates() {
  echo "# Reports are shaped with the skill's own templates"
  has "$BUILD" 'Templates are in `templates/` next to this SKILL.md. Shape the returned report with it when persisting'
  has "$BUILD" '`templates/review.md` for the Reviewer report'
  has "$BUILD" '`templates/verify.md` for the Verifier report'
  has "$BUILD" 'The Reviewer and Verifier prompts include no template.'
  lacks "$BUILD" '.ai-factory/templates'
  local t
  for t in review verify; do
    if [ -f "plugin/skills/factory-build/templates/$t.md" ]; then
      ok "plugin/skills/factory-build/templates/$t.md exists"
    else
      bad "plugin/skills/factory-build/templates/$t.md exists"
    fi
  done
}

# Scenario: Invoking subagents uses the installed-agent contract
scenario_invoking_subagents() {
  echo "# Invoking subagents uses the installed-agent contract"
  local expected actual
  expected='Wherever this skill says *invoke the `factory-<name>` subagent*:
- **Cursor**: delegate by name, e.g. `/factory-<name> <input>`.
- **Claude Code**: call the Agent tool with `subagent_type: factory-<name>`.
The installed agents live in `~/.claude/agents/`; a project `.claude/agents/factory-<name>.md`
overrides one by each tool'"'"'s own precedence. Pass only the inputs this skill names
(paths, task IDs, inlined template content).'
  # The prose: the section up to its first blank line.
  actual=$(awk '
    $0 == "## Invoking subagents" { found = 1; next }
    found && NF { print; started = 1; next }
    found && started { exit }
  ' "$BUILD")
  same "Invoking subagents prose is the installed-agent contract" "$expected" "$actual"
  lacks "$BUILD" 'sync.sh'
  lacks "$BUILD" '.ai-factory/framework'
  if grep -qiE 'generated adapter|adapters' "$BUILD"; then
    bad "$BUILD does not mention generated adapters"
  else
    ok "$BUILD does not mention generated adapters"
  fi
}

scenario_checks_keyed_by_labels
scenario_required_placeholder
scenario_required_none
scenario_required_missing_or_empty
scenario_optional_not_configured
scenario_install_format_never_run
scenario_all_configured_pass
scenario_configured_check_fails
scenario_wording_contract
scenario_no_unconditional_skip
scenario_output_floor
scenario_frontmatter
scenario_precondition
scenario_step_c_routes_to_human
scenario_revisions_and_missing_command
scenario_project_override_notice
scenario_skill_templates
scenario_invoking_subagents

if [ "$FAILED" -ne 0 ]; then
  echo "test-verifier-gate: FAILED"
  exit 1
fi
echo "test-verifier-gate: all checks passed"
