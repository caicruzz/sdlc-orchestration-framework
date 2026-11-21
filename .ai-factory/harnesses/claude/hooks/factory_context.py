#!/usr/bin/env python3
"""Solo AI Factory: context handoff hooks for Claude Code.

Registered for two events (see the Claude Code INSTALL.md):

- PostToolUse: while a factory build is active (a build-state.md with Status
  `active`), reads the token usage of the newest main-conversation response
  from the session transcript. At `handoff_at_percent` of the context window
  (config.md `## Build`, default 70), and again at 90%, it tells the
  orchestrator to follow the factory-build Context handoff section.
- SessionStart: after a compaction during an active build, points the
  orchestrator back to build-state.md. In a fresh or cleared session, says
  that a handoff is pending so "resume the factory build" picks it up.

Usage counts input, cache creation and cache read tokens, the same figure the
Claude Code status line reports as `used_percentage`. The window size is not
in hook input: pass `--window 1000000` for a 1M-context model. Without it the
script assumes 200,000, or 1,000,000 once usage passes 200,000.

Standard library only. Any error exits 0 silently, so the session is never
blocked by this hook.
"""

import json
import os
import re
import sys
import tempfile

DEFAULT_PERCENT = 70
SECOND_WARNING = 90
DEFAULT_WINDOW = 200_000
LARGE_WINDOW = 1_000_000
TAIL_BYTES = 4 * 1024 * 1024


def find_root(start):
    path = os.path.abspath(start)
    while True:
        if os.path.isdir(os.path.join(path, ".ai-factory")):
            return path
        parent = os.path.dirname(path)
        if parent == path:
            return None
        path = parent


def build_states(root):
    projects = os.path.join(root, ".ai-factory", "state", "projects")
    states = []
    try:
        slugs = sorted(os.listdir(projects))
    except OSError:
        return states
    pattern = re.compile(r"^\|\s*\*\*Status\*\*\s*\|\s*`?([a-z-]+)`?", re.I | re.M)
    for slug in slugs:
        path = os.path.join(projects, slug, "build-state.md")
        try:
            with open(path, encoding="utf-8") as handle:
                match = pattern.search(handle.read())
        except OSError:
            continue
        if match:
            states.append({"slug": slug, "file": path, "status": match.group(1).lower()})
    return states


def handoff_percent(root):
    try:
        with open(os.path.join(root, ".ai-factory", "config.md"), encoding="utf-8") as handle:
            match = re.search(r"^\|\s*\*\*handoff_at_percent\*\*\s*\|\s*(\d+(?:\.\d+)?)", handle.read(), re.I | re.M)
        value = float(match.group(1)) if match else 0
        if 0 < value < 100:
            return value
    except (OSError, ValueError):
        pass
    return DEFAULT_PERCENT


def last_usage(transcript_path):
    """Input-side tokens of the newest main-conversation response, or None."""
    try:
        with open(transcript_path, "rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - TAIL_BYTES))
            lines = handle.read().decode("utf-8", errors="replace").splitlines()
    except OSError:
        return None
    for line in reversed(lines):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("type") != "assistant" or entry.get("isSidechain"):
            continue
        usage = (entry.get("message") or {}).get("usage") or {}
        used = sum(
            int(usage.get(key) or 0)
            for key in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")
        )
        if used > 0:
            return used
    return None


def window_arg(argv):
    for index, arg in enumerate(argv):
        if arg == "--window" and index + 1 < len(argv):
            try:
                return int(argv[index + 1])
            except ValueError:
                return None
        if arg.startswith("--window="):
            try:
                return int(arg.split("=", 1)[1])
            except ValueError:
                return None
    return None


def marker_path(session_id):
    """Warn-level marker for this session, kept in the temp folder so it never
    lands on the state branch."""
    safe = re.sub(r"[^A-Za-z0-9_-]", "", session_id) or "unknown"
    return os.path.join(tempfile.gettempdir(), "factory-context-warnings", safe)


def warned_level(session_id):
    path = marker_path(session_id)
    try:
        with open(path, encoding="utf-8") as handle:
            return path, int(handle.read().strip() or 0)
    except (OSError, ValueError):
        return path, 0


def emit(event, text):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": event, "additionalContext": text}}))


def post_tool_use(data, root, states):
    if data.get("agent_id"):
        return  # A subagent's tool call, not the orchestrator's.
    active = [state for state in states if state["status"] == "active"]
    if not active or not data.get("transcript_path"):
        return
    used = last_usage(data["transcript_path"])
    if used is None:
        return
    window = window_arg(sys.argv[1:]) or (LARGE_WINDOW if used > DEFAULT_WINDOW else DEFAULT_WINDOW)
    percent = round(used * 100 / window)
    threshold = handoff_percent(root)
    if percent < threshold:
        return
    level = SECOND_WARNING if percent >= SECOND_WARNING else int(threshold)
    marker, previous = warned_level(data.get("session_id") or "unknown")
    if previous >= level:
        return
    try:
        os.makedirs(os.path.dirname(marker), exist_ok=True)
        with open(marker, "w", encoding="utf-8") as handle:
            handle.write(str(level))
    except OSError:
        pass
    files = ", ".join(state["file"] for state in active)
    emit(
        "PostToolUse",
        "Solo AI Factory: context usage is about %d%% (handoff_at_percent is %g). Follow the factory-build "
        "Context handoff section now: finish the steps in flight, update %s, and ask the user to clear the "
        "conversation and resume." % (percent, threshold, files),
    )


def session_start(data, root, states):
    source = data.get("source")
    if source in ("compact", "clear"):
        # Usage starts low again, so the next crossing should warn again.
        try:
            os.remove(marker_path(data.get("session_id") or "unknown"))
        except OSError:
            pass
    if source == "compact":
        active = [state for state in states if state["status"] == "active"]
        if active:
            files = ", ".join(state["file"] for state in active)
            emit(
                "SessionStart",
                "Solo AI Factory: this conversation was compacted during a factory build. Before any further "
                "build action, re-read %s and every task file, trust them over the summary, and follow the "
                "factory-build Context handoff section." % files,
            )
    elif source in ("startup", "clear"):
        pending = [state for state in states if state["status"] == "handoff-pending"]
        if pending:
            names = ", ".join("%s (%s)" % (state["slug"], state["file"]) for state in pending)
            emit(
                "SessionStart",
                "Solo AI Factory: a factory-build handoff is pending for %s. If the user asks to resume the "
                "build, invoke the factory-build skill and follow its Resume section." % names,
            )


def main():
    data = json.load(sys.stdin)
    root = find_root(os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd())
    if not root:
        return
    states = build_states(root)
    if not states:
        return
    event = data.get("hook_event_name")
    if event == "PostToolUse":
        post_tool_use(data, root, states)
    elif event == "SessionStart":
        session_start(data, root, states)


if __name__ == "__main__":
    try:
        main()
    except Exception:  # noqa: BLE001 - a hook must never break the session
        pass
    sys.exit(0)
