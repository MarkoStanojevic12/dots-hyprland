#!/usr/bin/env bash
# Renders a `script` log from a sidebar terminal as the plain text it showed.
# The raw log is every byte the pty wrote — fish's redraws, colour codes,
# progress bars rewritten with \r — so it is replayed through a headless tmux
# and the resulting screen plus scrollback is read back instead.
#
# usage: term-log.sh <log> [columns] [max-lines]
set -euo pipefail

log="${1:?usage: term-log.sh <log> [columns] [max-lines]}"
columns="${2:-120}"
maxLines="${3:-200}"
[[ -r "$log" ]] || { echo "no such log: $log" >&2; exit 1; }

socket="claude-term-render-$$"
trap 'tmux -L "$socket" kill-server 2>/dev/null || true' EXIT

tmux -L "$socket" -f <(echo 'set -g history-limit 100000') \
    new-session -d -x "$columns" -y 50 -e "LOG=$log" -e "SOCKET=$socket" \
    'stty -echo; cat "$LOG"; tmux -L "$SOCKET" wait-for -S rendered; sleep 60'
timeout 10 tmux -L "$socket" wait-for rendered

tmux -L "$socket" capture-pane -p -J -S - -E - \
    | grep -Ev '^Script (started|done) on ' \
    | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' \
    | tail -n "$maxLines"
