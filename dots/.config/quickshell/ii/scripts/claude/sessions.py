#!/usr/bin/env python3
"""Read Claude Code session transcripts for the sidebar's history picker.

Claude Code stores one JSONL transcript per conversation under
~/.claude/projects/<encoded-cwd>/<session-id>.jsonl. Subcommands:

    list <cwd>              -> [{id, title, mtime, turns, category}, ...]
    read <cwd> <session-id> -> [{role, text, model, tools: [...]}, ...]
    dirs                    -> [{path, sessions, mtime}, ...] newest first
    resolve <path>          -> {path, exists}
    retitle <cwd> <cli> [session-id] -> {updated: n}

All print a single JSON document on stdout.
"""

import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
PROJECTS = os.path.join(HOME, ".claude", "projects")
MAX_SESSIONS = 60
TITLE_LIMIT = 90

CATEGORIES = ("Coding", "Hyprland", "Misc")

# A path under any of these means the conversation was desktop-config work.
DESKTOP_MARKERS = (
    "/.config/hypr",
    "/.config/quickshell",
    "/.config/illogical-impulse",
    "/dots-hyprland",
)
# Neither signal: Claude's own state (a memory file is not "coding"), and the
# system tree, which every kind of conversation pokes at.
IGNORED_PREFIXES = (
    os.path.join(HOME, ".claude") + "/",
    "/usr/", "/etc/", "/opt/", "/var/", "/tmp/",
    "/proc/", "/sys/", "/dev/", "/run/", "/bin/", "/sbin/", "/lib/",
)

# Anchored paths only. A bare `modules/ii/bar/Bar.qml` cannot be placed --
# the shell's directory at the time is not in the transcript -- and guessing
# wrong files config work under whatever project the session was started in.
PATH_RE = re.compile(r"(?<![\w.\-/~])(?:~/[\w.\-/]+|/(?:[\w.\-]+/)+[\w.\-]+)")

STATE = os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")
TITLES_PATH = os.path.join(STATE, "quickshell", "user", "claude", "titles.json")
TITLE_MODEL = "claude-haiku-4-5-20251001"
TITLE_BATCH = 8  # Untitled conversations to name per `retitle` run.
DIGEST_PROMPTS = 8
DIGEST_CHARS = 240

TITLE_PROMPT = """\
You are naming Claude Code conversations for a sidebar history list.

For each conversation below, write a title of at most six words naming what
the person was trying to get done -- the goal, not the first thing they said.
No trailing period, no quotes, no conversation number.

Reply with nothing but a JSON array of {"id": "...", "title": "..."}."""


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


def tool_paths(message):
    """Every file path a turn's tool calls point at.

    Shell commands count too: with Bash-first tooling a whole conversation can
    touch files without a single `file_path` argument, which would otherwise
    read as if it had touched nothing.
    """
    for block in blocks_of(message):
        if block.get("type") != "tool_use":
            continue
        args = block.get("input")
        if not isinstance(args, dict):
            continue
        for key in ("file_path", "notebook_path", "path"):
            value = args.get(key)
            if isinstance(value, str) and value:
                yield value
        command = args.get("command")
        if isinstance(command, str):
            for match in PATH_RE.finditer(command):
                yield match.group(0)


def categorize(paths):
    """Bucket a conversation by the files it worked on.

    A majority vote rather than first-match: a coding session that glances at
    one config file is still a coding session.
    """
    desktop = 0
    code = 0
    for path in paths:
        absolute = os.path.join(HOME, path[2:]) if path.startswith("~/") else path
        if any(marker in absolute for marker in DESKTOP_MARKERS):
            desktop += 1
        elif not absolute.startswith(IGNORED_PREFIXES):
            code += 1
    if desktop and desktop >= code:
        return "Hyprland"
    if code:
        return "Coding"
    return "Misc"


def summarize(path, cwd):
    prompts = []
    turns = 0
    session = ""
    confirmed = False
    paths = set()

    for entry in entries(path):
        entry_cwd = entry.get("cwd")
        if entry_cwd and not confirmed:
            if entry_cwd != cwd:
                return None  # Belongs to a different directory.
            confirmed = True
        session = entry.get("sessionId") or session
        if is_typed_by_user(entry):
            turns += 1
            text = readable(text_of(entry.get("message") or {}))
            if text and len(prompts) < DIGEST_PROMPTS:
                prompts.append(text[:DIGEST_CHARS])
        elif entry.get("type") == "assistant":
            paths.update(tool_paths(entry.get("message") or {}))

    if not confirmed or turns == 0:
        return None
    return {
        "id": session or os.path.basename(path)[: -len(".jsonl")],
        "title": prompts[0][:TITLE_LIMIT] if prompts else "(no prompt)",
        "mtime": int(os.path.getmtime(path)),
        "turns": turns,
        "category": categorize(paths),
        "prompts": prompts,
    }


def load_titles():
    try:
        with open(TITLES_PATH) as handle:
            cached = json.load(handle)
    except (OSError, ValueError):
        return {}
    return cached if isinstance(cached, dict) else {}


def save_titles(titles):
    os.makedirs(os.path.dirname(TITLES_PATH), exist_ok=True)
    staging = TITLES_PATH + ".tmp"
    with open(staging, "w") as handle:
        json.dump(titles, handle, indent=1, sort_keys=True)
    os.replace(staging, TITLES_PATH)  # The sidebar reads this concurrently.


def milestone(turns):
    """Largest power of two at or below `turns`.

    A conversation's goal drifts fastest at the start, so the title is renewed
    when this moves -- turns 1, 2, 4, 8, 16 -- rather than on every turn.
    """
    return 1 << (turns.bit_length() - 1) if turns > 0 else 0


def needs_title(item, titles):
    cached = titles.get(item["id"])
    if not cached or not cached.get("title"):
        return True
    return milestone(item["turns"]) != milestone(cached.get("turns", 0))


def parse_titles(text):
    start = text.find("[")
    end = text.rfind("]")
    if start < 0 or end < start:
        return {}
    try:
        named = json.loads(text[start:end + 1])
    except ValueError:
        return {}
    if not isinstance(named, list):
        return {}
    titles = {}
    for item in named:
        if not isinstance(item, dict):
            continue
        key, title = item.get("id"), item.get("title")
        if isinstance(key, str) and isinstance(title, str) and title.strip():
            titles[key] = " ".join(title.split())[:TITLE_LIMIT]
    return titles


def ask_for_titles(cli, pending):
    conversations = "\n".join(
        '<conversation id="{}">\n{}\n</conversation>'.format(
            item["id"], "\n".join("user: " + prompt for prompt in item["prompts"])
        )
        for item in pending
    )
    try:
        finished = subprocess.run(
            [
                cli, "-p",
                "--model", TITLE_MODEL,
                # Leaves no transcript of its own, so naming conversations does
                # not add conversations to the list being named.
                "--no-session-persistence",
                "--restricted",
                "--strict-mcp-config",
                "--output-format", "text",
                TITLE_PROMPT + "\n\n" + conversations,
            ],
            cwd="/tmp",  # Away from any CLAUDE.md; the prompt is self-contained.
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=180,
        )
    except (OSError, subprocess.SubprocessError):
        return {}
    return parse_titles(finished.stdout)


def retitle(cwd, cli, session_id=""):
    if not cli:
        return {"updated": 0}
    titles = load_titles()
    if session_id:
        # The live conversation, named after every turn -- reading one
        # transcript instead of every transcript in the directory.
        path = session_path(cwd, session_id)
        found = [item for item in [summarize(path, cwd)] if item] if path else []
    else:
        found = scan(cwd)
    pending = [item for item in found if needs_title(item, titles)][:TITLE_BATCH]
    if not pending:
        return {"updated": 0}

    named = ask_for_titles(cli, pending)
    updated = 0
    for item in pending:
        title = named.get(item["id"])
        if title:
            titles[item["id"]] = {"title": title, "turns": item["turns"]}
            updated += 1
    if updated:
        save_titles(titles)
    return {"updated": updated}


def scan(cwd):
    """Every summary for `cwd`, newest first, digests still attached."""
    found = []
    for path in transcripts(cwd):
        summary = summarize(path, cwd)
        if summary:
            found.append(summary)
        if len(found) >= MAX_SESSIONS:
            break
    return found


def list_sessions(cwd):
    titles = load_titles()
    found = scan(cwd)
    for item in found:
        cached = titles.get(item["id"])
        if cached and cached.get("title"):
            item["title"] = cached["title"]
        # A generated title drops words the person actually typed, so the
        # opening prompt stays available for the search box to match on.
        prompts = item.pop("prompts")
        item["prompt"] = prompts[0][:TITLE_LIMIT] if prompts else ""
    found.sort(key=lambda item: (CATEGORIES.index(item["category"]), -item["mtime"]))
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


def session_path(cwd, session_id):
    if not session_id or "/" in session_id:
        return None
    for directory in project_dirs(cwd):
        path = os.path.join(directory, session_id + ".jsonl")
        if os.path.isfile(path):
            return path
    return None


def read_session(cwd, session_id):
    path = session_path(cwd, session_id)
    return conversation(path) if path else []


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
    elif len(args) >= 3 and args[0] == "retitle":
        result = retitle(args[1], args[2], args[3] if len(args) >= 4 else "")
    else:
        sys.stderr.write(
            "usage: sessions.py list <cwd> | read <cwd> <id> | dirs | resolve <path>"
            " | retitle <cwd> <cli> [session-id]\n"
        )
        return 2
    json.dump(result, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
