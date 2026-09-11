#!/usr/bin/env bash
# Renders an html code block from the Claude sidebar to a PNG, headlessly.
# Quickshell can't host WebEngine, so the picture is what goes in the chat.
# Usage: render-html.sh <content> <out.png> <width>
set -euo pipefail

content="${1:?content}"
out="${2:?out}"
width="${3:-460}"

mkdir -p "$(dirname "$out")"
html="${out%.png}.html"
printf '%s\n' "$content" > "$html"

# /usr/bin/qml is the Qt 5 runtime on Arch; the Qt 6 one is what has WebEngine.
qml=$(command -v qml6 || echo /usr/lib/qt6/bin/qml)
export QT_QPA_PLATFORM=offscreen
export QT_ASSUME_STDERR_HAS_CONSOLE=1
exec timeout 20 "$qml" "$(dirname "$0")/RenderHtml.qml" -- "$html" "$out" "$width"
