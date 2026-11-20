#!/usr/bin/env bash
# T001 layout test: plugin/ is the one source tree for agents and skills.
#
# Read-only. One function per scenario; each check prints "ok <check>" or
# "FAIL <check>". Exits non-zero if any check fails. Only lasting results are
# asserted here (what is on disk); facts about the change itself (100%
# renames, the README diff) are checked by the Reviewer.
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

absent() { [ ! -e "$1" ]; }

AGENTS="factory-architect factory-coder factory-evaluator factory-planner factory-reviewer factory-verifier"

# Scenario: Agents move to plugin/agents/ unchanged
scenario_agents_move_to_plugin() {
  echo "# Agents move to plugin/agents/ unchanged"
  local a f listed expected
  for a in $AGENTS; do
    check "plugin/agents/$a.md exists" test -f "plugin/agents/$a.md"
  done
  # Every entry, dotfiles included, in C-locale glob order.
  listed=""
  for f in plugin/agents/* plugin/agents/.[!.]* plugin/agents/..?*; do
    if [ -e "$f" ] || [ -L "$f" ]; then listed="$listed${f#plugin/agents/} "; fi
  done
  expected=""
  for a in $AGENTS; do expected="$expected$a.md "; done
  if [ "$listed" = "$expected" ]; then
    ok "plugin/agents/ holds exactly the six agents"
  else
    bad "plugin/agents/ holds exactly the six agents (found: $listed)"
  fi
  check ".ai-factory/framework/agents/ is gone" absent .ai-factory/framework/agents
}

# Scenario: Skills move to plugin/skills/ unchanged
scenario_skills_move_to_plugin() {
  echo "# Skills move to plugin/skills/ unchanged"
  local f
  for f in \
    plugin/skills/factory-archive/SKILL.md \
    plugin/skills/factory-archive/reference.md \
    plugin/skills/factory-build/SKILL.md \
    plugin/skills/factory-design/SKILL.md \
    plugin/skills/factory-plan/SKILL.md; do
    check "$f exists" test -f "$f"
  done
  check ".ai-factory/framework/ is gone" absent .ai-factory/framework
}

# Scenario: Each template is copied next to the one skill that uses it
scenario_templates_copied_next_to_skills() {
  echo "# Each template is copied next to the one skill that uses it"
  local pair skill name copy src
  for pair in \
    factory-design:design factory-design:evaluation \
    factory-plan:epic factory-plan:task \
    factory-build:review factory-build:verify; do
    skill=${pair%%:*}
    name=${pair#*:}
    copy="plugin/skills/$skill/templates/$name.md"
    src=".ai-factory/templates/$name.md"
    if [ -f "$copy" ] && [ -f "$src" ] && cmp -s "$copy" "$src"; then
      ok "$copy is byte-identical to $src"
    else
      bad "$copy is byte-identical to $src"
    fi
  done
  check "factory-archive has no templates/" absent plugin/skills/factory-archive/templates
}

# Scenario: The original templates stay for the factory that is running now
scenario_original_templates_stay() {
  echo "# The original templates stay for the factory that is running now"
  local name
  for name in design evaluation epic task review verify; do
    check ".ai-factory/templates/$name.md exists" test -f ".ai-factory/templates/$name.md"
  done
}

# Scenario: The setup skill's config template is left alone
scenario_setup_config_template_left_alone() {
  echo "# The setup skill's config template is left alone"
  check "plugin/skills/factory-setup/templates/config.md exists" \
    test -f plugin/skills/factory-setup/templates/config.md
  check ".ai-factory/config.md exists" test -f .ai-factory/config.md
}

# Scenario: Nothing else appears under plugin/
# (That agents/ and skills/ are the *only* entries holds for this task alone,
# since later tasks add evals/; the Reviewer checks it. Here: both exist.)
scenario_plugin_top_level() {
  echo "# Nothing else appears under plugin/"
  check "plugin/agents/ is a directory" test -d plugin/agents
  check "plugin/skills/ is a directory" test -d plugin/skills
}

# Scenario: The OAuth2 example moves to the repo root
scenario_example_moves_to_root() {
  echo "# The OAuth2 example moves to the repo root"
  local f
  for f in \
    examples/oauth2/00-design.md \
    examples/oauth2/evaluations/00-design-evaluation.md \
    examples/oauth2/tasks/T001-add-oauth-providers.md; do
    check "$f exists" test -f "$f"
  done
  check ".ai-factory/examples/ is gone" absent .ai-factory/examples
}

# Scenario: The example evaluation points at the new Design Doc path
scenario_example_evaluation_path() {
  echo "# The example evaluation points at the new Design Doc path"
  local line expected
  # shellcheck disable=SC2016 # backticks are literal Markdown
  expected='| **Design Doc** | `examples/oauth2/00-design.md` |'
  line=$(sed -n '7p' examples/oauth2/evaluations/00-design-evaluation.md 2>/dev/null || true)
  if [ "$line" = "$expected" ]; then
    ok "line 7 of the example evaluation names examples/oauth2/00-design.md"
  else
    bad "line 7 of the example evaluation names examples/oauth2/00-design.md (found: $line)"
  fi
  check "examples/oauth2/00-design.md (the path line 7 names) exists" test -f examples/oauth2/00-design.md
}

# Scenario: sync.sh and its CI check are deleted
scenario_generator_retired() {
  echo "# sync.sh and its CI check are deleted"
  check ".ai-factory/sync.sh is gone" absent .ai-factory/sync.sh
  check ".github/workflows/sync-check.yml is gone" absent .github/workflows/sync-check.yml
}

# readme_links: every [label](target) link target in the README, one per line.
readme_links() {
  grep -o '](\([^)]*\))' README.md | sed 's/^](//; s/)$//' || true
}

# Scenario: Stage-skill links in the README point into plugin/skills/
# (Line-number free: the README is rewritten by later tasks.)
scenario_readme_links_point_into_plugin() {
  echo "# Stage-skill links in the README point into plugin/skills/"
  local links want t skill path stray
  links=$(readme_links)
  for want in \
    plugin/skills/factory-design/SKILL.md \
    plugin/skills/factory-plan/SKILL.md \
    plugin/skills/factory-build/SKILL.md \
    plugin/skills/factory-archive/SKILL.md \
    plugin/skills/factory-archive/reference.md; do
    if printf '%s\n' "$links" | grep -qxF "$want"; then
      ok "README links to $want"
    else
      bad "README links to $want"
    fi
    check "README link target $want exists" test -e "$want"
  done
  # Every link labelled with a stage skill name targets that skill's SKILL.md.
  stray=""
  # shellcheck disable=SC2016 # backticks are literal Markdown
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    skill=${t#\[\`}
    skill=${skill%%\`*}
    path=${t#*](}
    path=${path%)}
    if [ "$path" != "plugin/skills/$skill/SKILL.md" ] || [ ! -e "$path" ]; then
      stray="$stray $t"
    fi
  done <<EOF
$(grep -o '\[`factory-[a-z]*`\]([^)]*)' README.md || true)
EOF
  if [ -z "$stray" ]; then
    ok "every stage-skill link in the README targets an existing plugin/skills/<skill>/SKILL.md"
  else
    bad "every stage-skill link in the README targets an existing plugin/skills/<skill>/SKILL.md (found:$stray)"
  fi
}

scenario_agents_move_to_plugin
scenario_skills_move_to_plugin
scenario_templates_copied_next_to_skills
scenario_original_templates_stay
scenario_setup_config_template_left_alone
scenario_plugin_top_level
scenario_example_moves_to_root
scenario_example_evaluation_path
scenario_generator_retired
scenario_readme_links_point_into_plugin

if [ "$FAILED" -ne 0 ]; then
  echo "test-plugin-layout: FAILED"
  exit 1
fi
echo "test-plugin-layout: all checks passed"
