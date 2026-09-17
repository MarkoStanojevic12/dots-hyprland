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

# Local whisper dictation service behind the Claude sidebar's mic button. The
# systemd unit is deliberately not synced: it carries the vocabulary hint, and
# that names the projects I work on.
rsync -a --delete \
  --exclude='.venv/' --exclude='__pycache__/' --exclude='*.pyc' \
  "$HOME/.local/share/whisper-dictate/" "dots/.local/share/whisper-dictate/"

# Hyprland config. Skip matugen-generated color files.
rsync -a \
  --exclude='*.new' \
  --exclude='hyprland/colors.lua' \
  --exclude='hyprlock/colors.conf' \
  "$CFG/hypr/" "$DST/hypr/"

echo "Synced. Review with 'git status' then commit."
