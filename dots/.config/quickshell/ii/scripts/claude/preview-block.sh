#!/usr/bin/env bash
# Opens an html or qml code block from the Claude sidebar in its own window.
# Usage: preview-block.sh <lang> <content>
set -euo pipefail

lang="${1:?lang}"
content="${2:?content}"

case "$lang" in
    html|htm|xhtml|svg) kind=html; ext=html ;;
    qml) kind=qml; ext=qml ;;
    *) echo "preview-block: no preview for '$lang'" >&2; exit 1 ;;
esac

dir="${XDG_RUNTIME_DIR:-/tmp}/claude-preview"
mkdir -p "$dir"
file="$dir/block-$$.$ext"
printf '%s\n' "$content" > "$file"

# /usr/bin/qml is the Qt 5 runtime on Arch; the Qt 6 one is what has WebEngine.
qml=$(command -v qml6 || echo /usr/lib/qt6/bin/qml)
exec "$qml" "$(dirname "$0")/PreviewWindow.qml" -- "$kind" "$file"
