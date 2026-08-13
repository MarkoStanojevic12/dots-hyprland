#!/usr/bin/env python3
"""Read Claude Code session transcripts for the sidebar's history picker.

Claude Code stores one JSONL transcript per conversation under
~/.claude/projects/<encoded-cwd>/<session-id>.jsonl. Subcommands:

    list <cwd>              -> [{id, title, mtime, turns}, ...] newest first
    read <cwd> <session-id> -> [{role, text, model, tools: [...]}, ...]
    dirs                    -> [{path, sessions, mtime}, ...] newest first
    resolve <path>          -> {path, exists}

All print a single JSON document on stdout.
"""

import json
import os
import sys

PROJECTS = os.path.expanduser("~/.claude/projects")
MAX_SESSIONS = 60
TITLE_LIMIT = 90


def project_dirs(cwd):
    """Directories that might hold transcripts for `cwd`.

    Claude Code encodes the working directory by replacing slashes with
    dashes. That is only a fast path — every entry carries its own `cwd`,
    which is what actually decides a match, so an encoding we don't predict
    degrades to a wider scan rather than an empty list.
    """
    encoded = os.path.join(PROJECTS, cwd.replace("/", "-"))
    if os.path.isdir(encoded):
        return [encoded]
    if not os.path.isdir(PROJECTS):
        return []
    return [
        os.path.join(PROJECTS, name)
        for name in os.listdir(PROJECTS)
        if os.path.isdir(os.path.join(PROJECTS, name))
    ]


def transcripts(cwd):
    """Every transcript path for `cwd`, newest first."""
    found = []
    for directory in project_dirs(cwd):
        for name in os.listdir(directory):
            if not name.endswith(".jsonl"):
                continue
            path = os.path.join(directory, name)
            try:
                found.append((os.path.getmtime(path), path))
            except OSError:
                continue
    found.sort(reverse=True)
    return [path for _, path in found]


def entries(path):
    try:
        handle = open(path, "r", errors="replace")
    except OSError:
        return
    with handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except ValueError:
                continue  # A partially written line; the rest is still good.


def blocks_of(message):
    content = message.get("content")
    if isinstance(content, list):
        return [block for block in content if isinstance(block, dict)]
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    return []


def text_of(message):
    return "".join(
        block.get("text", "")
        for block in blocks_of(message)
        if block.get("type") == "text"
    )


def is_tool_result(message):
    return any(block.get("type") == "tool_result" for block in blocks_of(message))


def is_typed_by_user(entry):
    """True for a prompt the person actually typed.

    Tool results come back as synthetic user messages, and slash commands
    arrive wrapped in caveat markup — neither belongs in the history view.
    """
    if entry.get("type") != "user" or entry.get("isSidechain") or entry.get("isMeta"):
        return False
    return not is_tool_result(entry.get("message") or {})


def readable(text):
    if "<local-command-caveat>" in text or text.lstrip().startswith("<command-"):
        return ""
    return " ".join(text.split())


def summarize(path, cwd):
    title = ""
    turns = 0
    session = ""
    confirmed = False

    for entry in entries(path):
        entry_cwd = entry.get("cwd")
        if entry_cwd and not confirmed:
            if entry_cwd != cwd:
                return None  # Belongs to a different directory.
            confirmed = True
        session = entry.get("sessionId") or session
        if is_typed_by_user(entry):
            turns += 1
            if not title:
                title = readable(text_of(entry.get("message") or {}))[:TITLE_LIMIT]

    if not confirmed or turns == 0:
        return None
    return {
        "id": session or os.path.basename(path)[: -len(".jsonl")],
        "title": title or "(no prompt)",
        "mtime": int(os.path.getmtime(path)),
        "turns": turns,
    }


def list_sessions(cwd):
    found = []
    for path in transcripts(cwd):
        summary = summarize(path, cwd)
        if summary:
            found.append(summary)
        if len(found) >= MAX_SESSIONS:
            break
    return found


def conversation(path):
    """Flatten a transcript into chat bubbles.

    One turn can span several assistant entries with tool calls between them,
    so consecutive assistant entries merge into a single bubble — matching how
    a live turn is rendered.
    """
    messages = []
    for entry in entries(path):
        if entry.get("isSidechain"):
            continue
        kind = entry.get("type")
        if kind not in ("user", "assistant"):
            continue
        message = entry.get("message") or {}

        if kind == "user":
            if not is_typed_by_user(entry):
                continue
            text = readable(text_of(message))
            if not text:
                continue
            messages.append({"role": "user", "text": text, "model": "", "tools": []})
            continue

        if not messages or messages[-1]["role"] != "assistant":
            messages.append({"role": "assistant", "text": "", "model": "", "tools": []})
        bubble = messages[-1]
        bubble["model"] = message.get("model") or bubble["model"]
        for block in blocks_of(message):
            if block.get("type") == "text":
                chunk = block.get("text") or ""
                if chunk:
                    bubble["text"] += ("\n\n" if bubble["text"] else "") + chunk
            elif block.get("type") == "tool_use":
                bubble["tools"].append({
                    "id": block.get("id") or "",
                    "name": block.get("name") or "",
                    "input": block.get("input") or {},
                })
    return messages


def read_session(cwd, session_id):
    if not session_id or "/" in session_id:
        return []
    for directory in project_dirs(cwd):
        path = os.path.join(directory, session_id + ".jsonl")
        if os.path.isfile(path):
            return conversation(path)
    return []


def directory_of(path):
    """The working directory a transcript belongs to, or None."""
    for entry in entries(path):
        if entry.get("cwd"):
            return entry["cwd"]
    return None


def list_dirs():
    """Directories Claude has been used in, newest first.

    Read out of the transcripts rather than decoded from the directory names:
    the encoding turns slashes into dashes, which cannot be reversed once a
    path contains dashes of its own (`~/Projects/some-desktop-app`).
    """
    found = {}
    if os.path.isdir(PROJECTS):
        for name in sorted(os.listdir(PROJECTS)):
            directory = os.path.join(PROJECTS, name)
            if not os.path.isdir(directory):
                continue
            paths = [
                os.path.join(directory, entry)
                for entry in os.listdir(directory)
                if entry.endswith(".jsonl")
            ]
            if not paths:
                continue
            paths.sort(key=os.path.getmtime, reverse=True)
            cwd = directory_of(paths[0])
            if not cwd or not os.path.isdir(cwd):
                continue  # Gone, renamed, or an unreadable transcript.
            existing = found.get(cwd)
            mtime = int(os.path.getmtime(paths[0]))
            if existing:
                existing["sessions"] += len(paths)
                existing["mtime"] = max(existing["mtime"], mtime)
            else:
                found[cwd] = {"path": cwd, "sessions": len(paths), "mtime": mtime}

    home = os.path.expanduser("~")
    if home not in found:
        found[home] = {"path": home, "sessions": 0, "mtime": 0}

    return sorted(found.values(), key=lambda item: item["mtime"], reverse=True)


def resolve(path):
    expanded = os.path.abspath(os.path.expanduser(os.path.expandvars(path.strip())))
    return {"path": expanded, "exists": os.path.isdir(expanded)}


def main():
    args = sys.argv[1:]
    if len(args) >= 2 and args[0] == "list":
        result = list_sessions(args[1])
    elif len(args) >= 3 and args[0] == "read":
        result = read_session(args[1], args[2])
    elif len(args) >= 1 and args[0] == "dirs":
        result = list_dirs()
    elif len(args) >= 2 and args[0] == "resolve":
        result = resolve(args[1])
    else:
        sys.stderr.write("usage: sessions.py list <cwd> | read <cwd> <id> | dirs | resolve <path>\n")
        return 2
    json.dump(result, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
