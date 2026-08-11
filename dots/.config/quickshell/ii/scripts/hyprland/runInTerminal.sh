#!/usr/bin/env bash
#
# Run a command block from the sidebar in a terminal.
#
# Prefers a terminal already open on the active workspace -- focusing that and
# typing into it beats leaving a trail of one-shot windows behind. Falls back to
# spawning a new terminal whenever there is nothing usable to reuse, which also
# covers every way the reuse path can fail.
#
# Usage: runInTerminal.sh <command-text> [fallback-terminal-argv...]

set -uo pipefail

command_text=${1-}
shift || true
fallback_terminal=("$@")

[[ -z $command_text ]] && exit 0

hypr_variables="$HOME/.config/hypr/hyprland/variables.lua"
user_shell=${SHELL:-/bin/bash}

# Every decision this makes is invisible once a window is on screen, and the
# failure modes look identical from the outside. Leave a trail.
log_file="${XDG_RUNTIME_DIR:-/tmp}/runInTerminal.log"
log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >>"$log_file" 2>/dev/null; }
log "--- click: shell=$user_shell fallback=[${fallback_terminal[*]-}]"

# Matched case-insensitively against the Hyprland window class.
terminal_classes='^(kitty|alacritty|foot|footclient|wezterm|org\.wezfurlong\.wezterm|konsole|ghostty|contour|rio|st|xterm|urxvt|terminator|tilix|gnome-terminal|org\.gnome\.terminal)$'

# The candidate list Super+T uses, read from the Hyprland config rather than
# copied, so the play button and the keybind can never disagree about what "the
# terminal" is. Same first-available rule that launch_first_available.sh applies.
terminal_candidates() {
    [[ -r $hypr_variables ]] || return 1
    sed -n 's/^[[:space:]]*terminal[[:space:]]*=[[:space:]]*"\(.*\)".*$/\1/p' "$hypr_variables" \
        | head -1 \
        | grep -o "'[^']*'" \
        | tr -d "'"
}

pick_terminal() {
    local candidate
    while IFS= read -r candidate; do
        [[ -z $candidate ]] && continue
        command -v "${candidate%% *}" >/dev/null 2>&1 || continue
        printf '%s\n' "$candidate"
        return 0
    done < <(terminal_candidates)
    return 1
}

# Terminals disagree about how a command is handed to them; the ones that take
# it bare (kitty, foot, ghostty) need nothing here.
terminal_exec_flag() {
    case "${1##*/}" in
        alacritty|konsole|xterm|uxterm|urxvt|terminator|tilix|gnome-terminal) printf -- '-e\n' ;;
        kgx) printf -- '--\n' ;;
        wezterm) printf 'start\n--\n' ;;
    esac
}

# A fresh window: run the block, then hand over to the login shell so what is
# left behind is the same terminal Super+T would have given you.
spawn() {
    local picked
    local -a term=() flag=()
    picked=$(pick_terminal) && read -r -a term <<< "$picked"
    [[ ${#term[@]} -eq 0 && ${#fallback_terminal[@]} -gt 0 ]] && term=("${fallback_terminal[@]}")
    [[ ${#term[@]} -eq 0 ]] && term=(kitty -1)
    mapfile -t flag < <(terminal_exec_flag "${term[0]}")
    log "spawn: ${term[*]} ${flag[*]-}"

    exec "${term[@]}" ${flag[@]+"${flag[@]}"} bash -c "$command_text
printf '\n─── exit %s ───\n' \"\$?\"
exec '$user_shell'"
}

for tool in hyprctl wtype jq; do
    command -v "$tool" >/dev/null 2>&1 || spawn
done

workspace=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty')
[[ -z $workspace ]] && spawn

# Of the terminals on this workspace, the one focused most recently is the one
# the user thinks of as "the terminal" -- focusHistoryID counts up from the
# currently focused window, so the lowest is the freshest.
address=$(hyprctl clients -j 2>/dev/null | jq -r \
    --argjson ws "$workspace" \
    --arg pattern "$terminal_classes" '
        [ .[]
          | select(.workspace.id == $ws)
          | select((.class // "") | ascii_downcase | test($pattern))
        ]
        | sort_by(.focusHistoryID)
        | first
        | .address // empty
    ')
log "workspace=$workspace candidate=${address:-none}"
[[ -z $address ]] && spawn

hyprctl dispatch "hl.dsp.focus({window=\"address:$address\"})" >/dev/null 2>&1

# The sidebar is a layer surface and holds the keyboard until the handover
# actually lands; typing early is how the command ended up in the chat box and
# got sent as a prompt. So poll until the terminal really is the active window,
# and if it never becomes so, open a fresh one rather than type somewhere
# unknown -- a stray window is recoverable, keystrokes into the wrong app aren't.
focused=""
for _ in $(seq 1 40); do
    sleep 0.05
    focused=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')
    [[ $focused == "$address" ]] && break
done
log "focus wanted=$address got=${focused:-none}"
[[ $focused == "$address" ]] || spawn

log "typing into $address"
# Window focus says nothing about which surface holds the keyboard, so there is
# nothing here to poll on — the sidebar's release is only ever a wait.
sleep 0.15
wtype -- "$command_text"
wtype -k Return
