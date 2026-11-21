#!/usr/bin/env python3
"""Solo AI Factory: context handoff hooks for Cursor.

Registered for two events (see the Cursor INSTALL.md):

- preCompact: Cursor reports context usage only here, and the hook cannot stop
  or change the compaction. While a factory build is active (a build-state.md
  with Status `active`), it shows the user a message: ask the orchestrator to
  hand off, then start a new chat and resume.
- sessionStart: in a new chat, says that a handoff is pending so "resume the
  factory build" picks it up.

Standard library only. Any error exits 0 silently, so the session is never
blocked by this hook.
"""

import json
import os
import re
import sys


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


def start_dir(data):
    roots = data.get("workspace_roots") or []
    return os.environ.get("CURSOR_PROJECT_DIR") or (roots[0] if roots else None) or os.getcwd()


def pre_compact(data, states):
    active = [state for state in states if state["status"] == "active"]
    if not active:
        return
    usage = data.get("context_usage_percent")
    at = " at %s%%" % round(float(usage)) if isinstance(usage, (int, float)) else ""
    slugs = ", ".join(state["slug"] for state in active)
    resume = " or ".join("resume the factory build for %s" % state["slug"] for state in active)
    print(json.dumps({
        "user_message": (
            "Solo AI Factory: Cursor is compacting the chat%s while the factory build for %s is running. "
            "Ask the orchestrator to hand off, then start a new chat and say: %s."
            % (at, slugs, resume)
        )
    }))


def session_start(states):
    pending = [state for state in states if state["status"] == "handoff-pending"]
    if not pending:
        return
    names = ", ".join("%s (%s)" % (state["slug"], state["file"]) for state in pending)
    print(json.dumps({
        "additional_context": (
            "Solo AI Factory: a factory-build handoff is pending for %s. If the user asks to resume the build, "
            "invoke the factory-build skill and follow its Resume section." % names
        )
    }))


def main():
    data = json.load(sys.stdin)
    root = find_root(start_dir(data))
    if not root:
        return
    states = build_states(root)
    if not states:
        return
    event = data.get("hook_event_name")
    if event == "preCompact":
        pre_compact(data, states)
    elif event == "sessionStart":
        session_start(states)


if __name__ == "__main__":
    try:
        main()
    except Exception:  # noqa: BLE001 - a hook must never break the session
        pass
    sys.exit(0)
