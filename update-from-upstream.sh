#!/usr/bin/env bash
# Pull the latest end-4/dots-hyprland, merge it with my customizations on the
# `personal` branch, apply the result to my live ~/.config, and reload.
# Safe to re-run: if a merge conflicts it stops so I can resolve, then re-run.
#
# Usage:  ./update-from-upstream.sh
set -euo pipefail
cd "$(dirname "$0")"

UPSTREAM_URL="https://github.com/end-4/dots-hyprland.git"
CFG="$HOME/.config"
DST="dots/.config"

# Don't clobber uncommitted repo edits.
if [ -n "$(git status --porcelain)" ]; then
    echo "!! Working tree not clean — commit or stash first." >&2
    exit 1
fi

# Ensure an 'upstream' remote pointing at end-4.
if ! git remote get-url upstream >/dev/null 2>&1; then
    git remote add upstream "$UPSTREAM_URL"
fi

echo ">> Fetching upstream..."
git fetch upstream

# Fast-forward main to upstream (main is a pristine tracking branch).
echo ">> Updating main..."
git checkout main
if ! git merge --ff-only upstream/main; then
    echo "!! main has diverged from upstream — reconcile manually." >&2
    exit 1
fi

# Merge upstream changes into my customizations.
echo ">> Merging into personal..."
git checkout personal
if ! git merge --no-edit main; then
    echo >&2
    echo "!! Merge conflicts. Resolve them, then:" >&2
    echo "     git add -A && git commit --no-edit" >&2
    echo "   and re-run this script to apply to live." >&2
    exit 1
fi

# Apply the merged config to the live setup. Same areas/exclusions as
# sync-personal.sh, reversed (repo -> live). matugen-generated files are never
# overwritten so theming stays intact.
echo ">> Applying to live ~/.config..."
rsync -a --delete \
    --exclude='__pycache__/' --exclude='*.pyc' --exclude='*.new' \
    "$DST/quickshell/ii/" "$CFG/quickshell/ii/"
rsync -a \
    --exclude='*.new' \
    --exclude='hyprland/colors.lua' \
    --exclude='hyprlock/colors.conf' \
    "$DST/hypr/" "$CFG/hypr/"

# Reload.
echo ">> Reloading Quickshell + Hyprland..."
touch "$CFG/quickshell/ii/shell.qml" 2>/dev/null || true
hyprctl reload >/dev/null 2>&1 || true

echo
echo "Done. Upstream merged and applied to live."
echo "If everything looks good:  git push origin personal main"
