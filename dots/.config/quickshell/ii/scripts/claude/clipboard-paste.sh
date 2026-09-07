#!/usr/bin/env bash
# Resolves a Ctrl+V in the Claude sidebar composer.
#
# Prints one of
#   image <media-type> <path>\n<base64 payload>
#   text\n<clipboard text>
# so an image never needs a second round trip to disk for its bytes, and the
# caller can tell the two cases apart before touching the input field.

set -uo pipefail

dir=${1:?target directory}
max_edge=${2:-1568}

emit_text() {
    printf 'text\n'
    wl-paste --no-newline 2>/dev/null
    exit 0
}

command -v wl-paste >/dev/null 2>&1 || { printf 'text\n'; exit 0; }

types=$(wl-paste --list-types 2>/dev/null)
mime=$(printf '%s\n' "$types" | grep -m1 -iE '^image/(png|jpeg|gif|webp|bmp)$')

mkdir -p "$dir"
grabbed="$dir/paste-$(date +%s%N)"

if [ -n "$mime" ]; then
    wl-paste --type "$mime" > "$grabbed" 2>/dev/null
elif printf '%s\n' "$types" | grep -qiE '^text/uri-list$'; then
    # A file copied in a file manager. Only images are worth attaching; every
    # other file is more useful to Claude as the path it was copied as.
    uri=$(wl-paste --type text/uri-list 2>/dev/null | head -n1 | tr -d '\r')
    [ "${uri#file://}" != "$uri" ] || emit_text
    path=${uri#file://}
    path=$(printf '%b' "${path//%/\\x}")
    mime=$(file -b --mime-type "$path" 2>/dev/null)
    case "$mime" in
        image/*) cp -- "$path" "$grabbed" 2>/dev/null ;;
        *) emit_text ;;
    esac
else
    emit_text
fi

[ -s "$grabbed" ] || { rm -f "$grabbed"; emit_text; }

# A full-screen screenshot is several megabytes of base64 for detail the model
# downsamples away anyway, so hand it over at the size it would have used.
if command -v magick >/dev/null 2>&1; then
    resized="$grabbed.png"
    if magick "$grabbed[0]" -resize "${max_edge}x${max_edge}>" "$resized" 2>/dev/null && [ -s "$resized" ]; then
        rm -f "$grabbed"
        grabbed=$resized
        mime=image/png
    fi
fi

case "$mime" in
    image/png | image/jpeg | image/gif | image/webp) ;;
    *) rm -f "$grabbed"; emit_text ;;
esac

printf 'image %s %s\n' "$mime" "$grabbed"
base64 -w0 "$grabbed"
