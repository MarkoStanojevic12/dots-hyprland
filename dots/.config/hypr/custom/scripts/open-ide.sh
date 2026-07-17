#!/usr/bin/env bash
# Opens Qt Creator (~2/3, left) + VS Code (~1/3, right) tiled side by side.
set -u

wait_for_class() {
    local pattern="$1"
    for _ in $(seq 1 60); do   # up to ~6s
        if hyprctl clients -j | jq -e --arg p "$pattern" \
            '.[] | select(.class | test($p; "i"))' >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

# 1. Go to a fresh workspace so your current windows aren't disturbed
hyprctl dispatch workspace empty

# 2. Qt Creator first -> left window
qtcreator &
wait_for_class "qtcreator"

# 3. VS Code -> dwindle tiles it to the right
code &
wait_for_class "^code"
sleep 0.3   # let it settle/focus

# 4. VS Code is focused (right window); set it to ~1/3 width.
#    Qt Creator reflows to the remaining ~2/3.
hyprctl dispatch resizeactive exact 33% 100%
