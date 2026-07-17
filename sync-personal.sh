#!/usr/bin/env bash
# Mirror my live ~/.config customizations into this fork's `dots/` tree so they
# can be committed. Only the areas I actually customize are synced, and
# matugen/fish-generated files are excluded (they churn on every theme change).
#
# Usage:  ./sync-personal.sh   then   git add -A && git commit
set -euo pipefail
cd "$(dirname "$0")"

CFG="$HOME/.config"
DST="dots/.config"

# Quickshell bar/shell config (temps, network, clipboard, etc.)
rsync -a --delete \
  --exclude='__pycache__/' --exclude='*.pyc' --exclude='*.new' \
  "$CFG/quickshell/ii/" "$DST/quickshell/ii/"

# Hyprland config. Skip matugen-generated color files.
rsync -a \
  --exclude='*.new' \
  --exclude='hyprland/colors.lua' \
  --exclude='hyprlock/colors.conf' \
  "$CFG/hypr/" "$DST/hypr/"

echo "Synced. Review with 'git status' then commit."
