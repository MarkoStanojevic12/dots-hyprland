#!/usr/bin/env bash
# Dictation for the Claude sidebar composer.
#
#   record <file> [endpoint] [model]      — record until killed, printing
#                                     partial <text so far>
#                                     loading <model being loaded>
#                                     final <transcript>   (and deletes <file>)
#   transcribe <file> [endpoint] [model]  — send it off and print one of
#                                     text\n<transcript>
#                                     error\n<what went wrong>
#   models [endpoint]             — list the ids the server will switch to,
#                                   the current one marked with a leading "* "
#
# Raw s16le rather than a wav: recording stops by killing the recorder, and a
# wav killed mid-write keeps the placeholder length in its header. pw-record
# and not parec — parec drops its whole buffer when it is sent SIGTERM.
#
# The transcript comes from /stream on the same server, so stopping is as fast
# as decoding the last second or so. If streaming is unavailable no `final` is
# printed and the recording is left behind for the caller to send to
# /transcribe instead.

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
    model=${4:-}
    [ -n "$endpoint" ] || endpoint=$DEFAULT_ENDPOINT
    mkdir -p "$(dirname "$file")"

    pw-record --raw --format=s16 --rate=16000 --channels=1 - >"$file" &
    recorder=$!
    trap 'kill "$recorder" 2>/dev/null' TERM INT EXIT

    stream=${endpoint%/transcribe}/stream
    session=$(curl -sS --max-time 5 -X POST "$stream/start?model=$model" 2>/dev/null)

    if [[ $session =~ ^[0-9]+$ ]]; then
        offset=0
        while kill -0 "$recorder" 2>/dev/null; do
            size=$(stat -c%s "$file" 2>/dev/null || echo 0)
            # 16000 Hz * 2 bytes: 0.2s of new audio per round trip. The request
            # is synchronous, so the loop paces itself off the decode instead of
            # a fixed interval — which is what lets a faster model feel faster.
            if [ "$((size - offset))" -lt 6400 ]; then
                sleep 0.05
                continue
            fi
            reply=$(tail -c "+$((offset + 1))" "$file" | head -c "$((size - offset))" |
                curl -sS --max-time 120 -X POST \
                    -H 'Content-Type: application/octet-stream' \
                    --data-binary @- -w $'\n%{http_code}' "$stream/chunk?id=$session" 2>/dev/null)
            offset=$size
            code=${reply##*$'\n'}
            text=$(printf '%s' "${reply%$'\n'*}" | tr '\n' ' ')
            case $code in
            # 202 is the model still coming off disk or the network; the audio
            # is buffered server-side, so the next chunk catches up.
            202) printf 'loading %s\n' "$text" ;;
            200) [ -n "${text//[[:space:]]/}" ] && printf 'partial %s\n' "$text" ;;
            esac
        done

        # Hand over the audio recorded since the last preview and take the
        # streamed transcript as the result: it is already as good as the
        # previews, and a second full pass costs seconds for the same words.
        size=$(stat -c%s "$file" 2>/dev/null || echo 0)
        final=$(tail -c "+$((offset + 1))" "$file" | head -c "$((size - offset))" |
            curl -sS --max-time 60 -X POST \
                -H 'Content-Type: application/octet-stream' \
                --data-binary @- "$stream/end?id=$session" 2>/dev/null | tr '\n' ' ')
        if [ -n "${final//[[:space:]]/}" ]; then
            printf 'final %s\n' "$final"
            rm -f "$file"
        fi
        # Nothing streamed back: leave the recording for the one-shot pass.
    else
        wait "$recorder" 2>/dev/null
    fi
    ;;

transcribe)
    file=${2:?source file}
    endpoint=${3:-}
    model=${4:-}
    [ -n "$endpoint" ] || endpoint=$DEFAULT_ENDPOINT
    [ -n "$model" ] && endpoint="$endpoint?model=$model"
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

models)
    endpoint=${2:-}
    [ -n "$endpoint" ] || endpoint=$DEFAULT_ENDPOINT
    curl -sS --max-time 5 "${endpoint%/transcribe}/models" 2>/dev/null
    ;;

*)
    emit error "usage: dictate.sh record|transcribe <file> | models"
    ;;
esac
