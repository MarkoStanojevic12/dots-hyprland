#!/usr/bin/env bash
# Opens the full working session:
#   ws1 = VS Code (top-left), GitKraken (bottom-left), Qt Creator (right)
#   ws2 = personal Chrome (left), work Chrome (top-right), client Chrome (bottom-right)
#   ws3 = Slack (left), WhatsApp (right)
#
# This config uses Hyprland's Lua parser, so `hyprctl keyword` is rejected outright
# and `hyprctl dispatch` takes a Lua expression, not the legacy "workspace 2" form.
# Both failure modes print to stdout and still exit 0, hence the checked hypr()
# wrapper below -- an unchecked call just silently does nothing.
#
# Workspace placement is declarative: a class -> workspace rule is injected per app
# and evaluated at map time, so it holds even when the window is created by an
# already-running process (Chrome) rather than the one we launched. `hyprctl reload`
# on exit drops those rules and restores the overridden options.
#
# Two options are overridden for the duration:
#   dwindle:force_split -> 2   dwindle picks the split AXIS from the parent's aspect
#                              ratio and the SIDE from this option, which is 0 here
#                              (side follows the mouse). Pinned so the layout does
#                              not depend on where the cursor happens to sit.
#   misc:focus_on_activate -> false
#                              GitKraken/Qt Creator/Code request activation seconds
#                              after their window maps, dragging the view back to
#                              their workspace while later windows are still opening.
set -u

CHROME=google-chrome-stable

# One entry per Chrome window, tabs in order; Chrome focuses the first.
# Profile 1 has three accounts signed in; the /u/N index follows sign-in order:
# u/0 = work, u/1 = personal, u/2 = client.
PERSONAL_TABS=("https://mail.google.com/mail/u/0/#inbox")
WHATSAPP_TABS=("https://web.whatsapp.com/")
WORK_TABS=("https://mail.google.com/mail/u/0/#inbox")
CLIENT_TABS=("https://mail.google.com/mail/u/2/#inbox")

# Internal hosts belong in none of this; the real lists live outside the config
# tree that gets mirrored to a public repo. Without the file, the defaults above
# stand and the session still opens.
LOCAL_TABS="$HOME/.config/illogical-impulse/session-tabs.sh"
# shellcheck source=/dev/null
[ -f "$LOCAL_TABS" ] && . "$LOCAL_TABS"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

notify() {
    command -v notify-send >/dev/null 2>&1 && notify-send "Session init" "$1"
    echo "session-init: $1" >&2
}

hypr() {
    local out
    out=$(hyprctl "$@" 2>&1)
    [ "$out" = "ok" ] && return 0
    notify "hyprctl $1 failed: ${out:-empty reply}"
    return 1
}

if [ "$FORCE" -eq 0 ] &&
    [ "$(hyprctl clients -j | jq '[.[] | select(.workspace.id == 1 or .workspace.id == 2 or .workspace.id == 3)] | length')" -gt 0 ]; then
    notify "Workspaces 1/2/3 are not empty. Close them first, or run with --force."
    exit 1
fi

trap 'hyprctl reload >/dev/null 2>&1' EXIT INT TERM

hypr eval 'hl.config({ misc = { focus_on_activate = false }, dwindle = { force_split = 2 } })'
[ "$(hyprctl -j getoption dwindle:force_split | jq -r '.int')" = "2" ] ||
    notify "could not pin dwindle:force_split -- the layout will likely be wrong"

# Class matching is a full match, so the patterns are anchored end to end.
hypr eval 'hl.window_rule({match = {class = "^code$"}, workspace = "1 silent"})'
hypr eval 'hl.window_rule({match = {class = "^org\\.qt-project\\.qtcreator$"}, workspace = "1 silent"})'
hypr eval 'hl.window_rule({match = {class = "^gitkraken$"}, workspace = "1 silent"})'
hypr eval 'hl.window_rule({match = {class = "^slack$"}, workspace = "3 silent"})'
hypr eval 'hl.window_rule({match = {class = "^google-chrome$"}, workspace = "2 silent"})'

LAST=""

# launch <workspace> <class-regex> <command...> -- runs it, waits for its window,
# stores the address in $LAST.
launch() {
    local ws="$1" class="$2" before got
    shift 2

    hypr dispatch "hl.dsp.focus({ workspace = $ws })"
    before=$(hyprctl clients -j | jq -c '[.[].address]')

    setsid "$@" >/dev/null 2>&1 &

    for _ in $(seq 1 300); do # up to ~30s
        LAST=$(hyprctl clients -j | jq -r --argjson b "$before" --arg c "$class" \
            'first(.[] | . as $w
                       | select(($w.class | test($c; "i")) and (($b | index($w.address)) == null))
                       | $w.address) // empty')
        [ -n "$LAST" ] && break
        sleep 0.1
    done

    if [ -z "$LAST" ]; then
        notify "timed out waiting for a window matching $class"
        return 1
    fi

    # Backstop for the workspace rule. Moving still tiles it next to that
    # workspace's last-focused window, so the intended split holds.
    got=$(hyprctl clients -j | jq -r --arg a "$LAST" '.[] | select(.address == $a) | .workspace.id')
    [ "$got" = "$ws" ] ||
        hypr dispatch "hl.dsp.window.move({ workspace = $ws, follow = false, window = \"address:$LAST\" })"

    sleep 0.4 # let it settle before it becomes a split parent
}

chrome_window() { # chrome_window <workspace> <profile-dir> <url...>
    local ws="$1" profile="$2"
    shift 2
    launch "$ws" '^google-chrome$' "$CHROME" --profile-directory="$profile" --new-window "$@"
}

focus() {
    local addr="$1"
    for _ in 1 2 3; do
        hypr dispatch "hl.dsp.focus({ window = \"address:$addr\" })"
        [ "$(hyprctl activewindow -j | jq -r '.address // empty')" = "$addr" ] && return 0
        sleep 0.2
    done
    notify "could not focus $addr; layout may be off"
    return 1
}

# resize <address> <width> <height|keep> -- "keep" re-sends the current height so
# only the width's split ratio moves.
resize() {
    local addr="$1" w="$2" h="$3"
    [ "$h" = keep ] && h=$(hyprctl clients -j | jq -r --arg a "$addr" '.[] | select(.address == $a) | .size[1]')
    focus "$addr" || return 1
    hypr dispatch "hl.dsp.window.resize({ x = $w, y = $h, \"exact\" })"
}

# --- Workspace 1 -------------------------------------------------------------
launch 1 '^code$' code || exit 1
CODE=$LAST
launch 1 '^org\.qt-project\.qtcreator$' qtcreator || exit 1 # wide parent -> splits right
focus "$CODE"
launch 1 '^gitkraken$' gitkraken || exit 1 # tall parent -> splits below

resize "$CODE" 1384 1049 # width hits the root split, height the code/gitkraken one

# --- Workspace 2 -------------------------------------------------------------
chrome_window 2 "Default" "${PERSONAL_TABS[@]}" || exit 1 # wide parent -> splits right
PERSONAL=$LAST
chrome_window 2 "Profile 1" "${WORK_TABS[@]}" || exit 1
WORK=$LAST
focus "$WORK"
chrome_window 2 "Profile 1" "${CLIENT_TABS[@]}" || exit 1 # tall parent -> splits below

# --- Workspace 3 -------------------------------------------------------------
launch 3 '^slack$' slack || exit 1 # wide parent -> splits right

# Later rules win at map time, so this redirects only the Chrome window opened
# after it; the ws2 windows above already mapped under the "2 silent" rule.
hypr eval 'hl.window_rule({match = {class = "^google-chrome$"}, workspace = "3 silent"})'
chrome_window 3 "Profile 1" "${WHATSAPP_TABS[@]}" || exit 1

hypr dispatch 'hl.dsp.focus({ workspace = 1 })'
