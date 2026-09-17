#!/usr/bin/env bash
# Dictation for the Claude sidebar composer.
#
#   record <file> [endpoint]      — record the default source until killed,
#                                   printing live previews as they arrive
#                                     partial <text so far>
#   transcribe <file> [endpoint]  — send it off and print one of
#                                     text\n<transcript>
#                                     error\n<what went wrong>
#
# Raw s16le rather than a wav: recording stops by killing the recorder, and a
# wav killed mid-write keeps the placeholder length in its header. pw-record
# and not parec — parec drops its whole buffer when it is sent SIGTERM.
#
# The previews come from /stream on the same server. They are a best effort: if
# the server is old or busy the loop goes quiet and recording is unaffected,
# because the transcript still comes from the one final /transcribe pass.

set -uo pipefail

DEFAULT_ENDPOINT=http://127.0.0.1:8765/transcribe

emit() {
    printf '%s\n%s' "$1" "${2:-}"
    exit 0
}

case ${1:-} in
record)
    file=${2:?target file}
    endpoint=${3:-}
    [ -n "$endpoint" ] || endpoint=$DEFAULT_ENDPOINT
    mkdir -p "$(dirname "$file")"

    pw-record --raw --format=s16 --rate=16000 --channels=1 - >"$file" &
    recorder=$!
    trap 'kill "$recorder" 2>/dev/null' TERM INT EXIT

    stream=${endpoint%/transcribe}/stream
    session=$(curl -sS --max-time 5 -X POST "$stream/start" 2>/dev/null)

    if [[ $session =~ ^[0-9]+$ ]]; then
        offset=0
        while kill -0 "$recorder" 2>/dev/null; do
            size=$(stat -c%s "$file" 2>/dev/null || echo 0)
            # 16000 Hz * 2 bytes: half a second of new audio per round trip,
            # so a fast decode does not turn into a request storm.
            if [ "$((size - offset))" -lt 16000 ]; then
                sleep 0.3
                continue
            fi
            text=$(tail -c "+$((offset + 1))" "$file" | head -c "$((size - offset))" |
                curl -sS --max-time 60 -X POST \
                    -H 'Content-Type: application/octet-stream' \
                    --data-binary @- "$stream/chunk?id=$session" 2>/dev/null | tr '\n' ' ')
            offset=$size
            [ -n "${text//[[:space:]]/}" ] && printf 'partial %s\n' "$text"
        done
        curl -sS --max-time 5 -X POST "$stream/end?id=$session" >/dev/null 2>&1
    else
        wait "$recorder" 2>/dev/null
    fi
    ;;

transcribe)
    file=${2:?source file}
    endpoint=${3:-}
    [ -n "$endpoint" ] || endpoint=$DEFAULT_ENDPOINT
    trap 'rm -f "$file"' EXIT

    size=$(stat -c%s "$file" 2>/dev/null || echo 0)
    # 16000 Hz * 2 bytes: under a third of a second is a misclick, not speech.
    [ "$size" -ge 10000 ] || emit error "Nothing recorded — check the input device"

    response=$(curl -sS --max-time 180 -X POST \
        -H 'Content-Type: application/octet-stream' \
        --data-binary "@$file" -w $'\n%{http_code}' "$endpoint" 2>&1)
    status=${response##*$'\n'}
    body=${response%$'\n'*}

    case $status in
    200) [ -n "${body//[[:space:]]/}" ] && emit text "$body" || emit error "Nothing was said" ;;
    000 | *[!0-9]*) emit error "Dictation server not running — systemctl --user start whisper-dictate" ;;
    *) emit error "$body" ;;
    esac
    ;;

*)
    emit error "usage: dictate.sh record|transcribe <file>"
    ;;
esac
