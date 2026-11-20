#!/usr/bin/env bash
# Runs the factory-setup behavioural evals in plugin/evals/ (paid, on demand).
#
# Usage: scripts/run-evals.sh --max-cost-usd <usd>
#
# Requires Claude Code v2.1.269 or later (`claude plugin eval`).
#
# Every eval run is a real model call billed to ANTHROPIC_API_KEY, so a cost
# ceiling (a positive number of US dollars) is required. The evals always
# exercise the skill in this checkout: `claude` runs with HOME set to a fresh
# temporary directory and with CLAUDE_CONFIG_DIR removed from its environment,
# so no factory-setup skill installed in the caller's ~/.claude (or custom
# config directory) is visible, and the run refuses to start if one would be.
# The temporary HOME has no stored login, which is why ANTHROPIC_API_KEY is
# required. An eval run is read-only unless --allow-tools grants more, so the
# run grants Write, Edit and `Bash(git *)` (granting Bash runs each command in
# Claude Code's OS sandbox). Exits with claude's exit code (2 when the cost
# ceiling stopped the run early).
#
# Never run from scripts/test.sh: it only picks up check.sh and test-*.sh.
set -euo pipefail

usage() {
  echo "usage: scripts/run-evals.sh --max-cost-usd <usd>" >&2
}

# is_positive_number <value>: a plain decimal number greater than zero.
is_positive_number() {
  case "$1" in
  "" | *[!0-9.]* | *.*.* | .) return 1 ;;
  esac
  case "$1" in
  *[1-9]*) return 0 ;;
  esac
  return 1
}

cap=""
while [ "$#" -gt 0 ]; do
  case "$1" in
  --max-cost-usd)
    if [ "$#" -lt 2 ] || ! is_positive_number "$2"; then
      usage
      exit 2
    fi
    cap="$2"
    shift 2
    ;;
  *)
    usage
    exit 2
    ;;
  esac
done
if [ -z "$cap" ]; then
  usage
  exit 2
fi

cd "$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "ANTHROPIC_API_KEY is required: evals run under a temporary HOME that has no stored login" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "claude not found on PATH: install Claude Code v2.1.269 or later to run evals" >&2
  exit 1
fi

eval_home="$(mktemp -d "${TMPDIR:-/tmp}/sif-evals.XXXXXX")"
trap 'rm -rf "$eval_home"' EXIT

if [ -e "$eval_home/.claude/skills/factory-setup" ] || [ -L "$eval_home/.claude/skills/factory-setup" ]; then
  echo "refusing to run: an installed factory-setup at $eval_home/.claude/skills/factory-setup would shadow the skill under test (plugin/skills/factory-setup)" >&2
  exit 1
fi

status=0
env -u CLAUDE_CONFIG_DIR HOME="$eval_home" claude plugin eval ./plugin \
  --scaffold --trust-plugin --ablation none \
  --allow-tools Write Edit "Bash(git *)" \
  --max-cost-usd "$cap" || status=$?
exit "$status"
