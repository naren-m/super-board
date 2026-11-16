#!/usr/bin/env python3
"""PreToolUse guard: a per-project deny list (fork).

Reads `.claude/super-board/deny.json` from the project root:

    {
      "read_paths":     ["tests/eval/heldout/"],
      "write_patterns": ["OLLAMA_BASE_URL\\\\s*[=:]\\\\s*[\\"']?https?://"],
      "reason":         "optional extra sentence shown to the agent"
    }

- read_paths: substrings. A Read/Grep/Glob path, or a Bash command, that mentions one
  is denied. Use it to keep lane agents away from data they must not see (a held-out
  eval set) — the agent cannot overfit to what it cannot open.
- write_patterns: regexes. Edit/Write/NotebookEdit content, or a Bash command, that
  matches one is denied. Use it for values that must never be committed (an internal
  endpoint). The matched text is never echoed.

No deny.json = no-op. Set SUPER_BOARD_DENY_BYPASS=1 in a session that is allowed to
read those paths (for example the eval grader you run yourself). Its own errors never
block a tool call.
"""
import json
import os
import re
import sys


def load():
    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    try:
        with open(os.path.join(root, ".claude", "super-board", "deny.json")) as fh:
            cfg = json.load(fh)
    except (OSError, ValueError):
        return [], [], ""
    paths = [p for p in cfg.get("read_paths") or [] if isinstance(p, str) and p]
    pats = []
    for p in cfg.get("write_patterns") or []:
        try:
            pats.append(re.compile(p, re.IGNORECASE))
        except re.error:
            pass
    return paths, pats, cfg.get("reason") or ""


def read_subject(tool, ti):
    if tool == "Bash":
        return ti.get("command") or ""
    if tool in ("Read", "NotebookRead"):
        return ti.get("file_path") or ti.get("notebook_path") or ""
    if tool in ("Grep", "Glob"):
        return " ".join(str(ti.get(k) or "") for k in ("path", "glob", "pattern"))
    return ""


def write_subject(tool, ti):
    if tool == "Write":
        return ti.get("content") or ""
    if tool in ("Edit", "MultiEdit"):
        return "\n".join([ti.get("new_string") or ""] +
                         [e.get("new_string") or "" for e in ti.get("edits") or []])
    if tool == "NotebookEdit":
        return ti.get("new_source") or ""
    if tool == "Bash":
        return ti.get("command") or ""
    return ""


def deny(why, extra):
    msg = "Blocked by guard-project-deny: " + why
    if extra:
        msg += " " + extra
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "permissionDecision": "deny",
                                             "permissionDecisionReason": msg}}))


def main():
    try:
        if os.environ.get("SUPER_BOARD_DENY_BYPASS") == "1":
            return
        payload = json.loads(sys.stdin.read() or "{}")
        tool = payload.get("tool_name") or ""
        ti = payload.get("tool_input") or {}
        paths, pats, extra = load()
        text = read_subject(tool, ti)
        for p in paths:
            if text and p in text:
                deny(f"this project keeps '{p}' off-limits to lane agents.", extra)
                return
        body = write_subject(tool, ti)
        for rx in pats:
            if body and rx.search(body):
                deny("this writes a value the project's deny list forbids committing; "
                     "use an environment variable or a <PLACEHOLDER>.", extra)
                return
    except Exception:
        pass  # fail open rather than block every call in the project


if __name__ == "__main__":
    main()
