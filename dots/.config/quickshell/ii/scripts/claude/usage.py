#!/usr/bin/env python3
"""Fetch the account's plan usage limits for the sidebar's context tooltip.

Same endpoint `/usage` reads, authenticated with the OAuth token `claude login`
left in ~/.claude/.credentials.json. Prints a single JSON document:

    {"limits": [{key, label, utilization, resetsAt, usedDollars, limitDollars}, ...]}
    {"error": "..."}

`resetsAt` is epoch seconds (0 when unknown). Limits the API reports as null
are dropped.
"""
import json
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

URL = "https://api.anthropic.com/api/oauth/usage"

# The response also carries internal codenames; those keep their key as label
# unless they hold a dollar balance, which is always extra-usage credit.
LABELS = {
    "five_hour": "5h",
    "seven_day": "Week",
    "seven_day_opus": "Week (Opus)",
    "seven_day_sonnet": "Week (Sonnet)",
    "seven_day_oauth_apps": "Week (apps)",
    "seven_day_cowork": "Week (Cowork)",
}


def epoch(value):
    if not value:
        return 0
    try:
        return int(datetime.fromisoformat(value).timestamp())
    except ValueError:
        return 0


def main():
    try:
        creds = json.loads((Path.home() / ".claude/.credentials.json").read_text())
        token = creds["claudeAiOauth"]["accessToken"]
    except (OSError, KeyError, ValueError) as e:
        print(json.dumps({"error": f"no credentials: {e}"}))
        return

    request = urllib.request.Request(URL, headers={
        "Authorization": f"Bearer {token}",
        "anthropic-beta": "oauth-2025-04-20",
    })
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            data = json.load(response)
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        return

    limits = []
    for key, entry in data.items():
        if not isinstance(entry, dict) or entry.get("utilization") is None:
            continue
        dollars = entry.get("limit_dollars")
        label = LABELS.get(key) or ("Extra usage" if dollars else key.replace("_", " "))
        limits.append({
            "key": key,
            "label": label,
            "utilization": entry["utilization"],
            "resetsAt": epoch(entry.get("resets_at")),
            "usedDollars": entry.get("used_dollars"),
            "limitDollars": dollars,
        })
    print(json.dumps({"limits": limits}))


if __name__ == "__main__":
    sys.exit(main())
