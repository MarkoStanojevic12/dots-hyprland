#!/usr/bin/env python3
"""Live state of the tickets, PRs and Sentry issues the Claude sidebar draws as link cards.

    link-meta.py CACHE_FILE REF...

REF is one of
    jira:<host>:<KEY>            through scripts/jira/jira.sh, so only the site in jira.json
    gh-pr:<owner>/<repo>#<n>     through gh
    gh-issue:<owner>/<repo>#<n>  through gh
    sentry:<org>:<issue id>      with the token in ~/.sentryclirc

Prints {ref: entry} for the refs asked about and merges them into CACHE_FILE. A failed
lookup keeps what was known before and records the error, so a card offline still shows
its last good state.
"""
import configparser
import fcntl
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import urlparse

JIRA_SH = Path(__file__).resolve().parent.parent / "jira" / "jira.sh"
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "illogical-impulse"
KEEP_SECONDS = 30 * 24 * 3600


def run(cmd):
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=25)
    if out.returncode != 0:
        try:
            message = json.loads(out.stdout)["error"]
        except (ValueError, KeyError, TypeError):
            message = out.stderr.strip() or out.stdout.strip() or f"exit {out.returncode}"
        raise RuntimeError(message.splitlines()[0][:200] if message else "failed")
    return json.loads(out.stdout)


def jira(host, key):
    site = json.loads((CONFIG / "jira.json").read_text()).get("site", "")
    if urlparse(site).hostname != host:
        raise RuntimeError(f"{host} is not the site in jira.json")
    d = run([str(JIRA_SH), "brief", key])
    return {"title": d.get("summary"), "status": d.get("status"),
            "statusCategory": d.get("statusCategory"), "type": d.get("type")}


def gh_pr(repo, number):
    d = run(["gh", "pr", "view", number, "-R", repo, "--json", "title,state,isDraft,additions,deletions"])
    state = (d.get("state") or "").title()
    if state == "Open" and d.get("isDraft"):
        state = "Draft"
    return {"title": d.get("title"), "state": state,
            "additions": d.get("additions"), "deletions": d.get("deletions")}


def gh_issue(repo, number):
    d = run(["gh", "issue", "view", number, "-R", repo, "--json", "title,state,stateReason"])
    state = (d.get("state") or "").title()
    if state == "Closed" and d.get("stateReason") == "NOT_PLANNED":
        state = "Not planned"
    return {"title": d.get("title"), "state": state}


def sentry(org, issue):
    rc = configparser.ConfigParser()
    rc.read(Path.home() / ".sentryclirc")
    token = rc.get("auth", "token", fallback="").strip()
    if not token:
        raise RuntimeError("no token in ~/.sentryclirc")
    # The token only ever goes to the configured Sentry, never to a host taken from a link.
    base = rc.get("defaults", "url", fallback="https://sentry.io").rstrip("/")
    request = urllib.request.Request(f"{base}/api/0/organizations/{org}/issues/{issue}/",
                                     headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            d = json.load(response)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}") from None
    return {"shortId": d.get("shortId"), "title": d.get("title"),
            "status": (d.get("status") or "").title(), "events": int(d.get("count") or 0),
            "users": d.get("userCount"), "lastSeen": d.get("lastSeen")}


PATTERNS = [
    (re.compile(r"jira:([a-z0-9-]+\.atlassian\.net):([A-Z][A-Z0-9]+-\d+)"), jira),
    (re.compile(r"gh-pr:([\w.-]+/[\w.-]+)#(\d+)"), gh_pr),
    (re.compile(r"gh-issue:([\w.-]+/[\w.-]+)#(\d+)"), gh_issue),
    (re.compile(r"sentry:([a-z0-9-]+):(\d+)"), sentry),
]


def lookup(ref):
    for pattern, fetch in PATTERNS:
        m = pattern.fullmatch(ref)
        if m:
            try:
                return fetch(*m.groups()), None
            except Exception as e:  # Any failure is just a card without live state
                return None, str(e) or type(e).__name__
    return None, "unknown ref"


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cache = Path(sys.argv[1])
    refs = list(dict.fromkeys(sys.argv[2:]))
    with ThreadPoolExecutor(max_workers=6) as pool:
        results = dict(zip(refs, pool.map(lookup, refs)))

    cache.parent.mkdir(parents=True, exist_ok=True)
    now = time.time()
    with open(cache.with_name(cache.name + ".lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            data = json.loads(cache.read_text())
        except (OSError, ValueError):
            data = {}
        for ref, (fields, error) in results.items():
            if error is None:
                data[ref] = {**fields, "fetched": now}
            else:
                known = {k: v for k, v in data.get(ref, {}).items() if k != "error"}
                data[ref] = {**known, "fetched": now, "error": error}
        data = {ref: entry for ref, entry in data.items() if now - entry.get("fetched", 0) < KEEP_SECONDS}
        cache.write_text(json.dumps(data, ensure_ascii=False))
    print(json.dumps({ref: data[ref] for ref in refs}, ensure_ascii=False))


if __name__ == "__main__":
    main()
