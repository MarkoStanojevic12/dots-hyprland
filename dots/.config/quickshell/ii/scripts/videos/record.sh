#!/usr/bin/env bash

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
JSON_PATH=".screenRecord.savePath"

CUSTOM_PATH=$(jq -r "$JSON_PATH" "$CONFIG_FILE" 2>/dev/null)

RECORDING_DIR=""

if [[ -n "$CUSTOM_PATH" ]]; then
    RECORDING_DIR="$CUSTOM_PATH"
else
    RECORDING_DIR="$HOME/Videos" # Use default path
fi

# Remembers what the currently running wf-recorder is writing to, so the stop
# invocation (a separate process) can name the file it just produced.
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/quickshell-recording-path"

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}
getaudiooutput() {
    pactl list sources | grep 'Name' | grep 'monitor' | cut -d ' ' -f2
}
getactivemonitor() {
    hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
}

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

# parse --region <value> without modifying $@ so other flags like --fullscreen still work
ARGS=("$@")
MANUAL_REGION=""
SOUND_FLAG=0
FULLSCREEN_FLAG=0
for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[i]}" == "--region" ]]; then
        if (( i+1 < ${#ARGS[@]} )); then
            MANUAL_REGION="${ARGS[i+1]}"
        else
            notify-send "Recording cancelled" "No region specified for --region" -a 'Recorder' & disown
            exit 1
        fi
    elif [[ "${ARGS[i]}" == "--sound" ]]; then
        SOUND_FLAG=1
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    fi
done

if pgrep wf-recorder > /dev/null; then
    RECORDED_FILE=""
    [[ -r "$STATE_FILE" ]] && RECORDED_FILE="$(cat "$STATE_FILE")"

    # Stop first so the container is finalized before anyone opens or copies it
    pkill wf-recorder
    rm -f "$STATE_FILE"

    # The body is the file path on purpose: the shell's copy button turns a body
    # that points at an existing file into a clipboard file reference.
    # -A implies --wait, so this has to stay backgrounded until the user answers
    (
        if [[ "$(notify-send "Recording Stopped" "${RECORDED_FILE:-Stopped}" -a 'Recorder' -A "open=Open folder")" == "open" ]]; then
            dolphin "$RECORDING_DIR"
        fi
    ) & disown
else
    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        AREA_ARGS=(-o "$(getactivemonitor)")
    else
        # If a manual region was provided via --region, use it; otherwise run slurp as before.
        if [[ -n "$MANUAL_REGION" ]]; then
            region="$MANUAL_REGION"
        else
            if ! region="$(slurp 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
                exit 1
            fi
        fi
        AREA_ARGS=(--geometry "$region")
    fi

    FILENAME="recording_$(getdate).mp4"
    printf '%s' "$RECORDING_DIR/$FILENAME" > "$STATE_FILE"

    # No body: there is nothing to copy yet, and an empty body is what makes the
    # shell drop the copy button. The path shows up in the stop notification.
    notify-send "Starting recording" -a 'Recorder' & disown

    if [[ $SOUND_FLAG -eq 1 ]]; then
        wf-recorder "${AREA_ARGS[@]}" --pixel-format yuv420p -f "./$FILENAME" -t --audio="$(getaudiooutput)"
    else
        wf-recorder "${AREA_ARGS[@]}" --pixel-format yuv420p -f "./$FILENAME" -t
    fi
fi
