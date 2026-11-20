#!/usr/bin/env bash
# T006 test: scripts/run-evals.sh and the factory-setup eval cases in
# plugin/evals/.
#
# No paid calls: a stub `claude` placed first on PATH records its arguments,
# HOME and working directory instead of running evals, and a stub `mktemp`
# stands in when a test needs the runner to see a pre-made HOME. The runner
# always runs with HOME set to a fake caller home under the temporary root, so
# the real $HOME is never touched. Every temporary directory lives under one
# root in ${TMPDIR:-/tmp} that is removed on exit.
#
# One function per scenario; each check prints "ok <check>" or "FAIL <check>".
# Exits non-zero if any check fails.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_ROOT=$(pwd -P)
RUNNER="$REPO_ROOT/scripts/run-evals.sh"
EVALS="plugin/evals"
CFG=".ai-factory/config.md"

# Bare assignment so set -e stops the run if mktemp fails; canonicalise in a
# separate step (macOS: /var -> /private/var).
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-run-evals.XXXXXX")
TMP_ROOT=$(cd "$TMP_ROOT" && pwd -P)
case "$TMP_ROOT" in
/ | "$REPO_ROOT" | "$REPO_ROOT"/*)
  echo "refusing to use temporary directory '$TMP_ROOT'" >&2
  exit 1
  ;;
esac
trap 'rm -rf "$TMP_ROOT"' EXIT

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
# has <file> <fixed string>: the file contains the string.
has() { [ -f "$1" ] && grep -qF -- "$2" "$1"; }
lacks() { ! has "$1" "$2"; }
# contains <haystack> <needle>
contains() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

EXPECTED_CASES="already-set-up
confirmation-gate
empty-repo
go-plain
node-npm-init
partial-lint-gap
polyglot-makefile
polyglot-no-runner
python-uv-ruff
python-with-prettier-package-json
redetect-keeps-values"
DEFAULT_PROMPT="Set up the factory in this repo. Apply the proposal without asking me."

# ---------------------------------------------------------------------------
# Runner harness
# ---------------------------------------------------------------------------

STUB_BIN="$TMP_ROOT/bin"          # stub claude
MKTEMP_BIN="$TMP_ROOT/mktemp-bin" # stub mktemp (refusal tests only)
STUB_LOG="$TMP_ROOT/claude.log"
EVAL_TMP="$TMP_ROOT/tmp" # TMPDIR the runner sees
CALLER_HOME="$TMP_ROOT/caller-home"
ELSEWHERE="$TMP_ROOT/elsewhere" # a cwd outside the repository
mkdir -p "$STUB_BIN" "$MKTEMP_BIN" "$EVAL_TMP" "$ELSEWHERE"

# The caller has factory-setup installed in their (fake) home.
mkdir -p "$CALLER_HOME/.claude/skills/factory-setup"
printf '%s\n' "---" "name: factory-setup" "---" "installed copy" \
  >"$CALLER_HOME/.claude/skills/factory-setup/SKILL.md"

cat >"$STUB_BIN/claude" <<'EOF'
#!/usr/bin/env bash
{
  printf 'HOME=%s\n' "$HOME"
  printf 'PWD=%s\n' "$(pwd -P)"
  if [ -d "$HOME" ]; then echo "HOME_EXISTS=yes"; else echo "HOME_EXISTS=no"; fi
  if [ -e "$HOME/.claude/skills/factory-setup" ]; then echo "SKILL_VISIBLE=yes"; else echo "SKILL_VISIBLE=no"; fi
  if [ -n "${CLAUDE_CONFIG_DIR+set}" ]; then
    printf 'CLAUDE_CONFIG_DIR=%s\n' "$CLAUDE_CONFIG_DIR"
  else
    echo "CLAUDE_CONFIG_DIR=__unset__"
  fi
  for a in "$@"; do printf 'ARG=%s\n' "$a"; done
} >"$STUB_LOG"
exit "${STUB_EXIT:-0}"
EOF
chmod +x "$STUB_BIN/claude"

# PREMADE_HOME is what the stub mktemp hands out.
PREMADE_HOME="$EVAL_TMP/sif-evals.premade"
cat >"$MKTEMP_BIN/mktemp" <<EOF
#!/usr/bin/env bash
mkdir -p "$PREMADE_HOME"
printf '%s\n' "$PREMADE_HOME"
EOF
chmod +x "$MKTEMP_BIN/mktemp"

# A PATH holding only the tools the runner needs besides claude (symlinks to
# the real ones), for the missing-claude test.
NOCLAUDE_BIN="$TMP_ROOT/noclaude-bin"
mkdir -p "$NOCLAUDE_BIN"
for tool in dirname mktemp rm env; do
  ln -s "$(command -v "$tool")" "$NOCLAUDE_BIN/$tool"
done

OUT=""
ERR=""
RC=0
STUB_EXIT=0
# CALLER_CONFIG_DIR: the caller's CLAUDE_CONFIG_DIR (__unset__ = not set).
CALLER_CONFIG_DIR=__unset__
# PATH_ONLY: when non-empty, the runner's whole PATH (no stub claude).
PATH_ONLY=""

# run_evals <cwd> <api key | __unset__> <extra PATH prefix | -> [args...]
# Runs the runner with the fake caller HOME and the stub claude first on PATH;
# sets OUT, ERR and RC. The stub log is cleared first.
run_evals() {
  local cwd="$1" key="$2" pre="$3"
  shift 3
  local path="$STUB_BIN:$PATH"
  if [ "$pre" != - ]; then path="$pre:$path"; fi
  if [ -n "$PATH_ONLY" ]; then path="$PATH_ONLY"; fi
  local cmd=(env -u ANTHROPIC_API_KEY -u CLAUDE_CONFIG_DIR HOME="$CALLER_HOME"
    TMPDIR="$EVAL_TMP" PATH="$path" STUB_LOG="$STUB_LOG" STUB_EXIT="$STUB_EXIT")
  if [ "$key" != __unset__ ]; then cmd+=(ANTHROPIC_API_KEY="$key"); fi
  if [ "$CALLER_CONFIG_DIR" != __unset__ ]; then
    cmd+=(CLAUDE_CONFIG_DIR="$CALLER_CONFIG_DIR")
  fi
  cmd+=("$BASH" "$RUNNER")
  rm -f "$STUB_LOG"
  RC=0
  (cd "$cwd" && "${cmd[@]}" "$@") >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" </dev/null || RC=$?
  OUT=$(cat "$TMP_ROOT/out")
  ERR=$(cat "$TMP_ROOT/err")
}

claude_not_called() { [ ! -e "$STUB_LOG" ]; }
claude_called() { [ -f "$STUB_LOG" ]; }
rc_is() { [ "$RC" -eq "$1" ]; }
err_has() { contains "$ERR" "$1"; }
log_value() { sed -n "s/^$1=//p" "$STUB_LOG" | head -n 1; }
log_args() { sed -n 's/^ARG=//p' "$STUB_LOG"; }
no_eval_home_left() { [ -z "$(ls -A "$EVAL_TMP")" ]; }

USAGE="scripts/run-evals.sh --max-cost-usd <usd>"

# Scenario: Runner requires a cost cap
scenario_runner_requires_a_cost_cap() {
  echo "# Runner requires a cost cap"
  run_evals "$REPO_ROOT" test-key -
  check "no arguments: exit 2" rc_is 2
  check "no arguments: usage on stderr" err_has "$USAGE"
  check "no arguments: nothing on stdout" test -z "$OUT"
  check "no arguments: claude not called" claude_not_called
  run_evals "$REPO_ROOT" test-key - --max-cost-usd
  check "--max-cost-usd without a value: exit 2" rc_is 2
  check "--max-cost-usd without a value: usage on stderr" err_has "$USAGE"
  check "--max-cost-usd without a value: claude not called" claude_not_called
  run_evals "$REPO_ROOT" test-key - --max-cost-usd ""
  check "--max-cost-usd with an empty value: exit 2" rc_is 2
  check "--max-cost-usd with an empty value: claude not called" claude_not_called
  run_evals "$REPO_ROOT" __unset__ -
  check "no cap and no API key: usage wins (exit 2)" rc_is 2
  local bad_cap
  for bad_cap in 0 0.00 -1 abc 1.2.3 . 1e3 5usd; do
    run_evals "$REPO_ROOT" test-key - --max-cost-usd "$bad_cap"
    check "--max-cost-usd $bad_cap (not a positive number): exit 2" rc_is 2
    check "--max-cost-usd $bad_cap: usage on stderr" err_has "$USAGE"
    check "--max-cost-usd $bad_cap: claude not called" claude_not_called
  done
  check "no eval HOME was created" no_eval_home_left
}

# Scenario: Unknown arguments are rejected
scenario_unknown_arguments_are_rejected() {
  echo "# Unknown arguments are rejected"
  run_evals "$REPO_ROOT" test-key - --max-cost-usd 5 --bogus
  check "--max-cost-usd 5 --bogus: exit 2" rc_is 2
  check "--max-cost-usd 5 --bogus: usage on stderr" err_has "$USAGE"
  check "--max-cost-usd 5 --bogus: claude not called" claude_not_called
  run_evals "$REPO_ROOT" test-key - --bogus --max-cost-usd 5
  check "--bogus first: exit 2" rc_is 2
  check "--bogus first: claude not called" claude_not_called
  run_evals "$REPO_ROOT" test-key - --max-cost-usd 5 extra
  check "a stray positional argument: exit 2" rc_is 2
  check "a stray positional argument: claude not called" claude_not_called
  check "no eval HOME was created" no_eval_home_left
}

# Scenario: Runner requires an API key
scenario_runner_requires_an_api_key() {
  echo "# Runner requires an API key"
  run_evals "$REPO_ROOT" __unset__ - --max-cost-usd 5
  check "unset key: exit 1" rc_is 1
  check "unset key: names ANTHROPIC_API_KEY as required" err_has "ANTHROPIC_API_KEY is required"
  check "unset key: explains the temporary HOME has no stored login" err_has "temporary HOME that has no stored login"
  check "unset key: claude not called" claude_not_called
  run_evals "$REPO_ROOT" "" - --max-cost-usd 5
  check "empty key: exit 1" rc_is 1
  check "empty key: names ANTHROPIC_API_KEY as required" err_has "ANTHROPIC_API_KEY is required"
  check "empty key: claude not called" claude_not_called
  check "no eval HOME was created" no_eval_home_left
}

# Scenario: Runner uses a fresh temporary HOME
scenario_runner_uses_a_fresh_temporary_home() {
  echo "# Runner uses a fresh temporary HOME"
  local home expected actual
  check "scripts/run-evals.sh is executable" test -x "$RUNNER"
  check "scripts/run-evals.sh uses #!/usr/bin/env bash" \
    test "$(head -n 1 "$RUNNER")" = "#!/usr/bin/env bash"

  STUB_EXIT=7
  CALLER_CONFIG_DIR="$CALLER_HOME/.claude"
  run_evals "$ELSEWHERE" test-key - --max-cost-usd 5
  CALLER_CONFIG_DIR=__unset__
  STUB_EXIT=0
  check "claude was called" claude_called
  check "exits with claude's exit code (7)" rc_is 7
  home=$(log_value HOME 2>/dev/null || true)
  case "$home" in
  "$EVAL_TMP"/sif-evals.?*) ok "HOME is a new directory under \${TMPDIR:-/tmp} ($home)" ;;
  *) bad "HOME is a new directory under \${TMPDIR:-/tmp} (got '$home')" ;;
  esac
  check "HOME is not the caller's HOME" test "$home" != "$CALLER_HOME"
  check "HOME existed while claude ran" test "$(log_value HOME_EXISTS)" = yes
  check "claude ran from the repository root, not the caller's cwd" \
    test "$(log_value PWD)" = "$REPO_ROOT"
  # One ARG= line per argument, so "Bash(git *)" must arrive as one argument.
  expected=$(printf '%s\n' plugin eval ./plugin --scaffold --trust-plugin --ablation none \
    --allow-tools Write Edit "Bash(git *)" --max-cost-usd 5)
  actual=$(log_args)
  check "invocation is exactly: claude plugin eval ./plugin --scaffold --trust-plugin --ablation none --allow-tools Write Edit \"Bash(git *)\" --max-cost-usd 5" \
    test "$actual" = "$expected"
  check "CLAUDE_CONFIG_DIR set by the caller is not passed to claude" \
    test "$(log_value CLAUDE_CONFIG_DIR)" = __unset__
  check "temporary HOME removed afterwards" test ! -e "$home"
  check "nothing left under \${TMPDIR:-/tmp}" no_eval_home_left

  run_evals "$REPO_ROOT/scripts" test-key - --max-cost-usd 0.5
  check "run from scripts/: exits with claude's exit code (0)" rc_is 0
  check "run from scripts/: claude ran from the repository root" \
    test "$(log_value PWD)" = "$REPO_ROOT"
  check "the cap is passed through as given (0.5)" \
    test "$(log_args | tail -n 1)" = "0.5"
  check "run from scripts/: temporary HOME removed afterwards" no_eval_home_left
}

# Scenario: Runner refuses when an installed factory-setup is visible
scenario_runner_refuses_when_installed_factory_setup_visible() {
  echo "# Runner refuses when an installed factory-setup is visible"
  mkdir -p "$PREMADE_HOME/.claude/skills/factory-setup"
  printf 'installed\n' >"$PREMADE_HOME/.claude/skills/factory-setup/SKILL.md"
  run_evals "$REPO_ROOT" test-key "$MKTEMP_BIN" --max-cost-usd 5
  check "installed directory: exit 1" rc_is 1
  check "installed directory: says it would shadow the skill under test" \
    err_has "would shadow the skill under test"
  check "installed directory: claude not called" claude_not_called
  rm -rf "$PREMADE_HOME"

  # A dangling symlink still counts as installed.
  mkdir -p "$PREMADE_HOME/.claude/skills"
  ln -s "$TMP_ROOT/does-not-exist" "$PREMADE_HOME/.claude/skills/factory-setup"
  run_evals "$REPO_ROOT" test-key "$MKTEMP_BIN" --max-cost-usd 5
  check "dangling symlink: exit 1" rc_is 1
  check "dangling symlink: says it would shadow the skill under test" \
    err_has "would shadow the skill under test"
  check "dangling symlink: claude not called" claude_not_called
  rm -rf "$PREMADE_HOME"
}

# home_snapshot <dir>: every path under it with a checksum of each file.
home_snapshot() {
  (cd "$1" && find . -print | LC_ALL=C sort | while IFS= read -r p; do
    if [ -f "$p" ] && [ ! -L "$p" ]; then
      printf '%s %s\n' "$p" "$(cksum <"$p")"
    else
      printf '%s\n' "$p"
    fi
  done)
}

# Scenario: The caller's real HOME is never touched
scenario_callers_real_home_never_touched() {
  echo "# The caller's real HOME is never touched"
  local before after home
  before=$(home_snapshot "$CALLER_HOME")
  # The caller also points CLAUDE_CONFIG_DIR at their ~/.claude.
  CALLER_CONFIG_DIR="$CALLER_HOME/.claude"
  run_evals "$ELSEWHERE" test-key - --max-cost-usd 5
  CALLER_CONFIG_DIR=__unset__
  after=$(home_snapshot "$CALLER_HOME")
  check "runner does not refuse because of the caller's installed skill" rc_is 0
  check "claude was called" claude_called
  home=$(log_value HOME)
  case "$home" in
  "$CALLER_HOME" | "$CALLER_HOME"/*) bad "claude's HOME is outside the caller's HOME (got '$home')" ;;
  *) ok "claude's HOME is outside the caller's HOME" ;;
  esac
  check "the caller's installed factory-setup is not visible to claude" \
    test "$(log_value SKILL_VISIBLE)" = no
  check "claude does not see the caller's CLAUDE_CONFIG_DIR" \
    test "$(log_value CLAUDE_CONFIG_DIR)" = __unset__
  check "nothing under the caller's ~/.claude changed" test "$before" = "$after"
}

# Review feedback (low): the runner reports a missing claude clearly, before
# creating a temporary HOME.
test_runner_reports_missing_claude() {
  echo "# Runner reports a missing claude"
  PATH_ONLY="$NOCLAUDE_BIN"
  run_evals "$REPO_ROOT" test-key - --max-cost-usd 5
  PATH_ONLY=""
  check "claude not on PATH: exit 1" rc_is 1
  check "claude not on PATH: says claude was not found" err_has "claude not found on PATH"
  check "claude not on PATH: names the minimum version" err_has "v2.1.269"
  check "claude not on PATH: no eval HOME was created" no_eval_home_left
}

# Review feedback (low): the runner's header names the minimum Claude Code
# version.
test_runner_header_names_minimum_version() {
  echo "# Runner header names the minimum Claude Code version"
  check "header comment mentions Claude Code v2.1.269" \
    test -n "$(sed -n '2,/^set -euo pipefail/p' "$RUNNER" | grep -F '# Requires Claude Code v2.1.269 or later')"
}

# ---------------------------------------------------------------------------
# Eval cases
# ---------------------------------------------------------------------------

actual_cases() {
  local d
  for d in "$EVALS"/*/; do
    d=${d%/}
    d=${d##*/}
    [ "$d" = results ] && continue
    printf '%s\n' "$d"
  done | LC_ALL=C sort
}

# grader_with <case> <fixed string>...: some single grader file of the case
# contains every string.
grader_with() {
  local c="$1" g s all
  shift
  for g in "$EVALS/$c"/graders/*.md; do
    [ -f "$g" ] || continue
    all=1
    for s in "$@"; do
      if ! grep -qF -- "$s" "$g"; then
        all=0
        break
      fi
    done
    [ "$all" -eq 1 ] && return 0
  done
  return 1
}

# Node evaluates the graders' JavaScript regexes the way `claude plugin eval`
# does. re_found <grader file> <target file>: exit 0 if the pattern is found.
RE_JS='
const fs = require("fs");
const [grader, target] = process.argv.slice(1);
const fm = fs.readFileSync(grader, "utf8").split("\n");
let pattern = null, flags = "";
for (const l of fm) {
  let m = l.match(/^pattern: \x27(.*)\x27$/);
  if (m) pattern = m[1].replace(/\x27\x27/g, "\x27");
  m = l.match(/^flags: (\S+)$/);
  if (m) flags = m[1];
}
if (pattern === null) process.exit(3);
const re = new RegExp(pattern, flags);
if (target === "-") process.exit(0);
process.exit(re.test(fs.readFileSync(target, "utf8")) ? 0 : 1);
'
have_node() { command -v node >/dev/null 2>&1; }
re_found() { node -e "$RE_JS" "$1" "$2"; }
re_not_found() {
  local rc=0
  node -e "$RE_JS" "$1" "$2" || rc=$?
  [ "$rc" -eq 1 ]
}
re_compiles() { node -e "$RE_JS" "$1" -; }

# scaffold <case> <dir>: run the case's fixture.sh in <dir> (created empty)
# with the minimal environment a scaffold script gets.
FX_HOME="$TMP_ROOT/fx-home"
FX_TMP="$TMP_ROOT/fx-tmp"
mkdir -p "$FX_HOME" "$FX_TMP"
scaffold() {
  mkdir -p "$2"
  (cd "$2" && env -i PATH="$PATH" HOME="$FX_HOME" TMPDIR="$FX_TMP" TERM=dumb \
    "$BASH" "$REPO_ROOT/$EVALS/$1/fixture.sh") >/dev/null 2>&1 </dev/null
}

# Scenario: Case inventory
scenario_case_inventory() {
  echo "# Case inventory"
  local c g n t work
  check "plugin/evals/ holds exactly the eleven cases" \
    test "$(actual_cases)" = "$EXPECTED_CASES"
  while IFS= read -r c; do
    check "$c: prompt.md" test -f "$EVALS/$c/prompt.md"
    check "$c: case.yaml" test -f "$EVALS/$c/case.yaml"
    check "$c: executable fixture.sh" test -x "$EVALS/$c/fixture.sh"
    check "$c: fixture.sh is bash" test "$(head -n 1 "$EVALS/$c/fixture.sh" 2>/dev/null)" = "#!/usr/bin/env bash"
    check "$c: case.yaml schema_version 1.1" has "$EVALS/$c/case.yaml" 'schema_version: "1.1"'
    check "$c: case.yaml name" has "$EVALS/$c/case.yaml" "name: $c"
    check "$c: case.yaml scaffold_script is fixture.sh" has "$EVALS/$c/case.yaml" "scaffold_script: fixture.sh"
    n=0
    for g in "$EVALS/$c"/graders/*.md; do
      [ -f "$g" ] || continue
      n=$((n + 1))
      t=$(sed -n 's/^type: //p' "$g" | head -n 1)
      case "$t" in
      file_exists | regex | tool_used) ok "$c: ${g##*/} is cost-free ($t)" ;;
      *) bad "$c: ${g##*/} is cost-free (type '$t')" ;;
      esac
    done
    check "$c: has graders" test "$n" -gt 0
    check "$c: a tool_used grader checks factory-setup fired" \
      grader_with "$c" "type: tool_used" "tool: Skill" "factory-setup"
  done <<EOF
$EXPECTED_CASES
EOF

  # Expected graders, per the inventory table.
  check "node-npm-init: Test unfilled" grader_with node-npm-init "path: $CFG" '\*\*Test\*\* \| <!--'
  check "node-npm-init: reply has the not-configured warning for Test" \
    grader_with node-npm-init "target: last_message" "not configured" "Test"
  check "python-uv-ruff: Test is uv run pytest" grader_with python-uv-ruff "path: $CFG" "Test" "uv run pytest"
  check "python-uv-ruff: Lint is ruff check ." grader_with python-uv-ruff "path: $CFG" "Lint" 'ruff check \.'
  check "go-plain: Test is go test ./..." grader_with go-plain "path: $CFG" "Test" 'go test \./\.\.\.'
  check "go-plain: Lint is go vet ./..." grader_with go-plain "path: $CFG" "Lint" 'go vet \./\.\.\.'
  check "polyglot-makefile: Test is make test" grader_with polyglot-makefile "path: $CFG" "Test" "make test"
  check "polyglot-makefile: Lint is make lint" grader_with polyglot-makefile "path: $CFG" "Lint" "make lint"
  check "polyglot-no-runner: Test unfilled" grader_with polyglot-no-runner "path: $CFG" '\*\*Test\*\* \| <!--'
  check "polyglot-no-runner: reason stated in the reply" \
    grader_with polyglot-no-runner "target: last_message" "unfilled" "polyglot"
  check "polyglot-no-runner: no && in the Test row" \
    grader_with polyglot-no-runner "path: $CFG" "match: not_contains" "Test" "&&"
  check "python-with-prettier-package-json: Python language" \
    grader_with python-with-prettier-package-json "path: $CFG" "Language" "Python"
  check "python-with-prettier-package-json: Python test command" \
    grader_with python-with-prettier-package-json "path: $CFG" "Test" "pytest"
  check "python-with-prettier-package-json: Python lint command" \
    grader_with python-with-prettier-package-json "path: $CFG" "Lint" "ruff check"
  check "python-with-prettier-package-json: no npm command" \
    grader_with python-with-prettier-package-json "path: $CFG" "match: not_contains" "npm"
  check "empty-repo: commands unfilled" grader_with empty-repo "path: $CFG" "match: not_contains" "Install|Test|Lint" "(?!<!--)"
  check "empty-repo: bullets unfilled" grader_with empty-repo "path: $CFG" "match: not_contains" '^- \*\*' "(?!<!--)"
  check "empty-repo: projects .gitkeep written" \
    grader_with empty-repo "type: file_exists" "path: .ai-factory/projects/.gitkeep" "exists: true"
  check "empty-repo: archive .gitkeep written" \
    grader_with empty-repo "type: file_exists" "path: .ai-factory/archive/.gitkeep" "exists: true"
  check "empty-repo: four .gitignore lines written" grader_with empty-repo "path: .gitignore" \
    '\.ai-factory/projects/\*$' '!\.ai-factory/projects/\.gitkeep$' '\.ai-factory/archive/\*$' '!\.ai-factory/archive/\.gitkeep$'
  check "already-set-up: reply says nothing to change" \
    grader_with already-set-up "target: last_message" "nothing to change"
  check "already-set-up: Write max 0" grader_with already-set-up "type: tool_used" "tool: Write" "min: 0" "max: 0"
  check "already-set-up: Edit max 0" grader_with already-set-up "type: tool_used" "tool: Edit" "min: 0" "max: 0"
  check "already-set-up: anchored config.md regex" grader_with already-set-up "path: $CFG" "pattern: '^# soloAIfactory" "\\n\$'"
  check "already-set-up: anchored .gitignore regex" grader_with already-set-up "path: .gitignore" "pattern: '^bin/" "\\n\$'"
  check "partial-lint-gap: anchored config.md regex" grader_with partial-lint-gap "path: $CFG" "pattern: '^# soloAIfactory" "\\n\$'"
  check "redetect-keeps-values: anchored config.md regex" \
    grader_with redetect-keeps-values "path: $CFG" "pattern: '^# soloAIfactory" "go test -race" "golangci-lint run"
  check "confirmation-gate: no config.md" \
    grader_with confirmation-gate "type: file_exists" "path: $CFG" "exists: false"
  check "confirmation-gate: no projects .gitkeep" \
    grader_with confirmation-gate "type: file_exists" "path: .ai-factory/projects/.gitkeep" "exists: false"
  check "confirmation-gate: no archive .gitkeep" \
    grader_with confirmation-gate "type: file_exists" "path: .ai-factory/archive/.gitkeep" "exists: false"

  if ! have_node; then
    echo "skip regex behaviour checks: node is not installed"
    return 0
  fi
  for g in "$EVALS"/*/graders/*.md; do
    if grep -q '^type: regex' "$g"; then
      check "${g#"$EVALS"/}: pattern is a valid JavaScript regex" re_compiles "$g"
    fi
  done

  work="$TMP_ROOT/regex"
  mkdir -p "$work"
  local G="$EVALS/already-set-up/graders"
  scaffold already-set-up "$work/already"
  check "already-set-up: config regex matches the scaffolded config.md" re_found "$G/config-unchanged.md" "$work/already/$CFG"
  check "already-set-up: .gitignore regex matches the scaffolded .gitignore" re_found "$G/gitignore-unchanged.md" "$work/already/.gitignore"
  cp "$work/already/$CFG" "$work/cfg" && printf 'x\n' >>"$work/cfg"
  check "already-set-up: config regex rejects an appended line" re_not_found "$G/config-unchanged.md" "$work/cfg"
  printf '.ai-factory/projects/*\n' >>"$work/already/.gitignore"
  check "already-set-up: .gitignore regex rejects an added factory line" re_not_found "$G/gitignore-unchanged.md" "$work/already/.gitignore"

  G="$EVALS/partial-lint-gap/graders"
  scaffold partial-lint-gap "$work/partial"
  check "partial-lint-gap: regex rejects the config with Lint still unfilled" re_not_found "$G/only-lint-changed.md" "$work/partial/$CFG"
  # shellcheck disable=SC2016 # literal backticks, not command substitution
  sed 's#^| \*\*Lint\*\* | .* | Required |$#| **Lint** | `go vet ./...` | Required |#' "$work/partial/$CFG" >"$work/cfg"
  check "partial-lint-gap: regex accepts Lint filled with go vet ./..." re_found "$G/only-lint-changed.md" "$work/cfg"
  sed 's#^| \*\*Install\*\* | .* | |$#| **Install** | go mod download | |#' "$work/cfg" >"$work/cfg2"
  check "partial-lint-gap: regex rejects another row changed too" re_not_found "$G/only-lint-changed.md" "$work/cfg2"

  G="$EVALS/redetect-keeps-values/graders"
  scaffold redetect-keeps-values "$work/redetect"
  check "redetect-keeps-values: regex accepts the unchanged config" re_found "$G/filled-rows-kept.md" "$work/redetect/$CFG"
  # shellcheck disable=SC2016 # literal backticks, not command substitution
  sed -e 's#^- \*\*Runtime\*\*: .*#- **Runtime**: Go 1.22#' \
    -e 's#^| \*\*Build\*\* | .* |#| **Build** | `go build ./...` | Optional |#' "$work/redetect/$CFG" >"$work/cfg"
  printf -- '- Ecosystem: Go\n' >>"$work/cfg"
  check "redetect-keeps-values: regex accepts unfilled rows being filled" re_found "$G/filled-rows-kept.md" "$work/cfg"
  sed 's#go test -race \./\.\.\.#go test ./...#' "$work/redetect/$CFG" >"$work/cfg"
  check "redetect-keeps-values: regex rejects a changed Test value" re_not_found "$G/filled-rows-kept.md" "$work/cfg"
  sed 's#golangci-lint run#go vet ./...#' "$work/redetect/$CFG" >"$work/cfg"
  check "redetect-keeps-values: regex rejects a changed Lint value" re_not_found "$G/filled-rows-kept.md" "$work/cfg"

  G="$EVALS/empty-repo/graders"
  local tmpl="plugin/skills/factory-setup/templates/config.md"
  check "empty-repo: commands regex finds nothing in the raw template" re_not_found "$G/commands-unfilled.md" "$tmpl"
  check "empty-repo: bullets regex finds nothing in the raw template" re_not_found "$G/bullets-unfilled.md" "$tmpl"
  sed 's#^| \*\*Test\*\* | .* | Required |$#| **Test** | make test | Required |#' "$tmpl" >"$work/cfg"
  check "empty-repo: commands regex finds a filled Test row" re_found "$G/commands-unfilled.md" "$work/cfg"
  sed 's#^- \*\*Language\*\*: .*#- **Language**: Go#' "$tmpl" >"$work/cfg"
  check "empty-repo: bullets regex finds a filled Language bullet" re_found "$G/bullets-unfilled.md" "$work/cfg"
  printf '%s\n' 'node_modules/' '.ai-factory/projects/*' '!.ai-factory/projects/.gitkeep' \
    '.ai-factory/archive/*' '!.ai-factory/archive/.gitkeep' >"$work/gi"
  check "empty-repo: .gitignore regex accepts the four lines" re_found "$G/gitignore-lines.md" "$work/gi"
  printf '%s\n' '.ai-factory/projects/*' '!.ai-factory/projects/.gitkeep' '.ai-factory/archive/*' >"$work/gi"
  check "empty-repo: .gitignore regex rejects three lines" re_not_found "$G/gitignore-lines.md" "$work/gi"

  G="$EVALS/polyglot-no-runner/graders"
  sed 's#^| \*\*Test\*\* | .* | Required |$#| **Test** | pytest \&\& go test ./... | Required |#' "$tmpl" >"$work/cfg"
  check "polyglot-no-runner: && regex finds a composed Test row" re_found "$G/test-row-has-no-and.md" "$work/cfg"
  check "polyglot-no-runner: && regex finds nothing in the raw template" re_not_found "$G/test-row-has-no-and.md" "$tmpl"
}

# prompt_body <prompt.md>: the text after the frontmatter, without the blank
# lines that separate it from the frontmatter.
prompt_body() {
  awk 'NR == 1 && $0 == "---" { fm = 1; next }
       fm && $0 == "---" { fm = 0; started = 0; next }
       fm { next }
       !started && $0 == "" { next }
       { started = 1; print }' "$1"
}

# Scenario: Default prompt
scenario_default_prompt() {
  echo "# Default prompt"
  local c body
  while IFS= read -r c; do
    body=$(prompt_body "$EVALS/$c/prompt.md" 2>/dev/null || true)
    case "$c" in
    redetect-keeps-values)
      check "$c: prompt asks to re-detect" contains "$body" "Re-detect"
      check "$c: prompt asks to apply without asking" contains "$body" "Apply the proposal without asking me."
      check "$c: prompt is not the default prompt" test "$body" != "$DEFAULT_PROMPT"
      ;;
    confirmation-gate)
      check "$c: prompt is exactly \"Set up the factory in this repo.\"" \
        test "$body" = "Set up the factory in this repo."
      ;;
    *)
      check "$c: prompt is exactly the default prompt" test "$body" = "$DEFAULT_PROMPT"
      ;;
    esac
  done <<EOF
$EXPECTED_CASES
EOF
}

# markers <case> <dir>: assert the files the case describes exist in <dir>.
markers() {
  local c="$1" d="$2"
  case "$c" in
  node-npm-init)
    check "$c: package.json with the npm-init placeholder test script" has "$d/package.json" 'no test specified'
    ;;
  python-uv-ruff)
    check "$c: pyproject.toml configures pytest" has "$d/pyproject.toml" "[tool.pytest.ini_options]"
    check "$c: pyproject.toml configures ruff" has "$d/pyproject.toml" "[tool.ruff]"
    check "$c: uv.lock" test -f "$d/uv.lock"
    check "$c: tests/test_x.py" test -f "$d/tests/test_x.py"
    ;;
  go-plain)
    check "$c: go.mod" test -f "$d/go.mod"
    check "$c: a _test.go file" test -f "$d/add_test.go"
    check "$c: no golangci config" test ! -e "$d/.golangci.yml" -a ! -e "$d/.golangci.yaml"
    ;;
  polyglot-makefile)
    check "$c: pyproject.toml" test -f "$d/pyproject.toml"
    check "$c: tests/test_x.py" test -f "$d/tests/test_x.py"
    check "$c: go.mod" test -f "$d/go.mod"
    check "$c: a _test.go file" test -f "$d/add_test.go"
    check "$c: Makefile has a test target" grep -q '^test:' "$d/Makefile"
    check "$c: Makefile has a lint target" grep -q '^lint:' "$d/Makefile"
    check "$c: Makefile recipes start with a tab" grep -q "$(printf '^\t')" "$d/Makefile"
    ;;
  polyglot-no-runner)
    check "$c: pyproject.toml" test -f "$d/pyproject.toml"
    check "$c: tests/test_x.py" test -f "$d/tests/test_x.py"
    check "$c: go.mod" test -f "$d/go.mod"
    check "$c: a _test.go file" test -f "$d/add_test.go"
    local r
    for r in Makefile justfile Taskfile.yml tox.ini noxfile.py; do
      check "$c: no $r" test ! -e "$d/$r"
    done
    ;;
  python-with-prettier-package-json)
    check "$c: pyproject.toml" test -f "$d/pyproject.toml"
    check "$c: tests/test_x.py" test -f "$d/tests/test_x.py"
    check "$c: package.json pins prettier" has "$d/package.json" '"prettier"'
    check "$c: package.json has no scripts" lacks "$d/package.json" '"scripts"'
    ;;
  empty-repo)
    check "$c: nothing but .git" test "$(ls -A "$d")" = ".git"
    check "$c: no commits" test -z "$(git -C "$d" rev-list --all 2>/dev/null)"
    ;;
  already-set-up)
    check "$c: config.md Test filled" grep -q '^| \*\*Test\*\* | `go test' "$d/$CFG"
    check "$c: config.md Lint filled" grep -q '^| \*\*Lint\*\* | `go vet' "$d/$CFG"
    check "$c: config.md Install unfilled" grep -q '^| \*\*Install\*\* | <!--' "$d/$CFG"
    check "$c: config.md Format unfilled" grep -q '^| \*\*Format\*\* | <!--' "$d/$CFG"
    check "$c: config.md Conventions unfilled" grep -q '^- \*\*Commit style\*\*: <!--' "$d/$CFG"
    check "$c: projects .gitkeep" test -f "$d/.ai-factory/projects/.gitkeep"
    check "$c: archive .gitkeep" test -f "$d/.ai-factory/archive/.gitkeep"
    check "$c: .gitignore without the factory lines" lacks "$d/.gitignore" ".ai-factory"
    ;;
  partial-lint-gap)
    check "$c: config.md Test filled" grep -q '^| \*\*Test\*\* | `go test' "$d/$CFG"
    check "$c: config.md Lint unfilled" grep -q '^| \*\*Lint\*\* | <!--' "$d/$CFG"
    check "$c: projects .gitkeep" test -f "$d/.ai-factory/projects/.gitkeep"
    check "$c: archive .gitkeep" test -f "$d/.ai-factory/archive/.gitkeep"
    ;;
  redetect-keeps-values)
    check "$c: config.md Test filled" grep -q '^| \*\*Test\*\* | `go test -race' "$d/$CFG"
    # shellcheck disable=SC2016 # literal backticks, not command substitution
    check "$c: config.md Lint filled" grep -q '^| \*\*Lint\*\* | `golangci-lint run`' "$d/$CFG"
    check "$c: config.md optional rows unfilled" grep -q '^| \*\*Type check\*\* | <!--' "$d/$CFG"
    check "$c: projects .gitkeep" test -f "$d/.ai-factory/projects/.gitkeep"
    check "$c: archive .gitkeep" test -f "$d/.ai-factory/archive/.gitkeep"
    ;;
  confirmation-gate)
    check "$c: go.mod (a marker repo)" test -f "$d/go.mod"
    check "$c: no .ai-factory yet" test ! -e "$d/.ai-factory"
    ;;
  esac
}

has_commit() { git -C "$1" rev-parse -q --verify HEAD >/dev/null; }

# tree_listing <dir>: every path outside .git with a checksum of each file.
tree_listing() {
  (cd "$1" && find . -path ./.git -prune -o -print | LC_ALL=C sort | while IFS= read -r p; do
    if [ -f "$p" ]; then printf '%s %s\n' "$p" "$(cksum <"$p")"; else printf '%s\n' "$p"; fi
  done)
}

# Scenario: Fixtures build their repos deterministically
scenario_fixtures_build_deterministically() {
  echo "# Fixtures build their repos deterministically"
  local c parent a b rc
  while IFS= read -r c; do
    parent="$TMP_ROOT/fx/$c"
    a="$parent/a"
    b="$parent/b"
    rc=0
    scaffold "$c" "$a" || rc=$?
    check "$c: fixture.sh exits 0" test "$rc" -eq 0
    check "$c: the directory is its own git repository" \
      test "$(git -C "$a" rev-parse --show-toplevel 2>/dev/null)" = "$a"
    markers "$c" "$a"
    check "$c: wrote nothing beside its directory" test "$(ls -A "$parent")" = "a"
    check "$c: wrote nothing into HOME" test -z "$(ls -A "$FX_HOME")"
    check "$c: wrote nothing into TMPDIR" test -z "$(ls -A "$FX_TMP")"
    rc=0
    scaffold "$c" "$b" || rc=$?
    check "$c: second run exits 0" test "$rc" -eq 0
    check "$c: second run builds the same files" test "$(tree_listing "$a")" = "$(tree_listing "$b")"
    if [ "$c" != empty-repo ]; then
      check "$c: has at least one commit" has_commit "$a"
      check "$c: commits have a fixed author" \
        test "$(git -C "$a" log --format='%an <%ae>' | LC_ALL=C sort -u)" = "soloAIfactory evals <evals@example.invalid>"
      check "$c: commits are made with commit.gpgsign=false" has "$EVALS/$c/fixture.sh" "commit.gpgsign=false"
      check "$c: second run makes the identical commit" \
        test "$(git -C "$a" rev-parse HEAD 2>/dev/null)" = "$(git -C "$b" rev-parse HEAD 2>/dev/null)"
    fi
  done <<EOF
$EXPECTED_CASES
EOF
}

# Scenario: Evals are never installed
scenario_evals_are_never_installed() {
  echo "# Evals are never installed"
  local e name extra manifest
  extra=""
  for e in plugin/agents/*; do
    name=${e##*/}
    case "$name" in factory-*.md) ;; *) extra="$extra $e" ;; esac
  done
  for e in plugin/skills/*; do
    name=${e##*/}
    if [ -d "$e" ]; then
      case "$name" in factory-*) ;; *) extra="$extra $e" ;; esac
    else
      extra="$extra $e"
    fi
  done
  check "plugin/agents and plugin/skills hold only factory-* entries" test -z "$extra"
  check "nothing eval-related under plugin/agents or plugin/skills" \
    test -z "$(find plugin/agents plugin/skills \( -name 'evals' -o -name 'fixture.sh' -o -name 'case.yaml' -o -name 'prompt.md' \) -print)"
  extra=""
  for e in plugin/* plugin/.[!.]*; do
    [ -e "$e" ] || continue
    case "${e##*/}" in agents | skills | evals | .claude-plugin) ;; *) extra="$extra $e" ;; esac
  done
  check "plugin/ holds only agents/, skills/, evals/ and .claude-plugin/" test -z "$extra"
  if [ -e plugin/.claude-plugin ]; then
    check "plugin/.claude-plugin holds only plugin.json" test "$(ls -A plugin/.claude-plugin)" = "plugin.json"
    manifest=$(tr -d ' \t\n' <plugin/.claude-plugin/plugin.json)
    check "plugin.json is name-only" test "$manifest" = '{"name":"soloaifactory"}'
  else
    ok "no plugin manifest"
  fi
}

# Scenario: Scripts are shellcheck-clean
scenario_scripts_are_shellcheck_clean() {
  echo "# Scripts are shellcheck-clean"
  if ! command -v shellcheck >/dev/null 2>&1; then
    echo "skip shellcheck: not installed"
    return 0
  fi
  local out rc=0
  out=$(shellcheck scripts/run-evals.sh scripts/test-run-evals.sh "$EVALS"/*/*.sh 2>&1) || rc=$?
  check "shellcheck exits 0" test "$rc" -eq 0
  check "shellcheck reports nothing" test -z "$out"
  [ -z "$out" ] || printf '%s\n' "$out"
}

scenario_runner_requires_a_cost_cap
scenario_unknown_arguments_are_rejected
scenario_runner_requires_an_api_key
scenario_runner_uses_a_fresh_temporary_home
scenario_runner_refuses_when_installed_factory_setup_visible
scenario_callers_real_home_never_touched
test_runner_reports_missing_claude
test_runner_header_names_minimum_version
scenario_case_inventory
scenario_default_prompt
scenario_fixtures_build_deterministically
scenario_evals_are_never_installed
scenario_scripts_are_shellcheck_clean

if [ "$FAILED" -ne 0 ]; then
  echo "test-run-evals: FAILED"
  exit 1
fi
echo "test-run-evals: all checks passed"
