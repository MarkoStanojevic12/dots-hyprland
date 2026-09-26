#!/usr/bin/env bash

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"

readconfig() { # $1 = jq path, $2 = fallback
    local value
    value="$(jq -r "$1 // empty" "$CONFIG_FILE" 2>/dev/null)"
    printf '%s' "${value:-$2}"
}

readbool() { # $1 = jq path, $2 = fallback as 0/1
    case "$(readconfig "$1" "")" in
        true) printf 1 ;;
        false) printf 0 ;;
        *) printf '%s' "$2" ;;
    esac
}

RECORDING_DIR="$(readconfig '.screenRecord.savePath' "$HOME/Videos")"

# Remembers what the currently running wf-recorder is writing to, so the stop
# invocation (a separate process) can name the file it just produced.
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/quickshell-recording-path"
# wf-recorder takes a single --audio device, so recording desktop and mic at the
# same time means mixing them into a null sink first. These are the module ids to
# unload again afterwards.
AUDIO_STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/quickshell-recording-audio-modules"
MIX_SINK="quickshell_record_mix"

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}
getactivemonitor() {
    hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
}
# The monitor of whatever sink is currently the default, so recordings follow the
# output the user is actually listening to instead of the first one pactl lists.
getdesktopsource() {
    local sink
    sink="$(pactl get-default-sink 2>/dev/null)"
    [[ -z "$sink" || "$sink" == @* ]] && return 1
    printf '%s.monitor' "$sink"
}
getmicsource() {
    local source
    source="$(pactl get-default-source 2>/dev/null)"
    # A monitor as the default source is desktop audio, not a microphone
    [[ -z "$source" || "$source" == @* || "$source" == *.monitor ]] && return 1
    printf '%s' "$source"
}

unloadaudiomodules() {
    [[ -r "$AUDIO_STATE_FILE" ]] || return 0
    local entries=()
    mapfile -t entries < "$AUDIO_STATE_FILE"
    rm -f "$AUDIO_STATE_FILE"
    # Reverse order: the loopbacks have to go before the sink they feed
    local i id name
    for ((i=${#entries[@]}-1;i>=0;i--)); do
        id="${entries[i]%%:*}"
        name="${entries[i]#*:}"
        # Module ids get reused, so only unload one that is still what we loaded
        if [[ "$(pactl list short modules 2>/dev/null | awk -v i="$id" '$1==i {print $2; exit}')" == "$name" ]]; then
            pactl unload-module "$id" 2>/dev/null
        fi
    done
}

setupmixsource() { # $1 = desktop source, $2 = mic source
    local ids=() id src loopbacks=0
    id="$(pactl load-module module-null-sink sink_name="$MIX_SINK" \
        sink_properties="device.description='Screen recording mix'" 2>/dev/null)" || return 1
    ids+=("$id:module-null-sink")
    for src in "$1" "$2"; do
        if id="$(pactl load-module module-loopback source="$src" sink="$MIX_SINK" latency_msec=30 2>/dev/null)"; then
            ids+=("$id:module-loopback")
            ((loopbacks++))
        fi
    done
    printf '%s\n' "${ids[@]}" > "$AUDIO_STATE_FILE"
    if (( loopbacks == 0 )); then
        unloadaudiomodules
        return 1
    fi
    printf '%s.monitor' "$MIX_SINK"
}

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

# parse --region <value> without modifying $@ so other flags like --fullscreen still work
ARGS=("$@")
MANUAL_REGION=""
FULLSCREEN_FLAG=0
# Audio defaults come from the config the bar's context menu writes; the flags
# below are per-invocation overrides.
DESKTOP_AUDIO=$(readbool '.screenRecord.desktopAudio' 1)
MIC_AUDIO=$(readbool '.screenRecord.microphone' 0)
for ((i=0;i<${#ARGS[@]};i++)); do
    case "${ARGS[i]}" in
        --region)
            if (( i+1 < ${#ARGS[@]} )); then
                MANUAL_REGION="${ARGS[i+1]}"
            else
                notify-send "Recording cancelled" "No region specified for --region" -a 'Recorder' & disown
                exit 1
            fi
            ;;
        --fullscreen) FULLSCREEN_FLAG=1 ;;
        --sound) DESKTOP_AUDIO=1 ;;
        --no-sound) DESKTOP_AUDIO=0 ;;
        --mic) MIC_AUDIO=1 ;;
        --no-mic) MIC_AUDIO=0 ;;
    esac
done

if pgrep wf-recorder > /dev/null; then
    RECORDED_FILE=""
    [[ -r "$STATE_FILE" ]] && RECORDED_FILE="$(cat "$STATE_FILE")"

    # Stop first so the container is finalized before anyone opens or copies it
    pkill wf-recorder
    rm -f "$STATE_FILE"
    # The mix modules are unloaded by the recording process's own EXIT trap, so
    # nothing to do here: tearing them down from this side would race with it.

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

    # Anything a SIGKILLed previous run left loaded, before taking the sink name
    unloadaudiomodules

    DESKTOP_SOURCE=""
    MIC_SOURCE=""
    (( DESKTOP_AUDIO )) && DESKTOP_SOURCE="$(getdesktopsource)"
    (( MIC_AUDIO )) && MIC_SOURCE="$(getmicsource)"

    AUDIO_ARGS=()
    if [[ -n "$DESKTOP_SOURCE" && -n "$MIC_SOURCE" ]]; then
        if MIX_SOURCE="$(setupmixsource "$DESKTOP_SOURCE" "$MIC_SOURCE")"; then
            AUDIO_ARGS=(--audio="$MIX_SOURCE")
        else
            notify-send "Recording without microphone" "Could not mix desktop audio and microphone" -a 'Recorder' & disown
            AUDIO_ARGS=(--audio="$DESKTOP_SOURCE")
        fi
    elif [[ -n "$DESKTOP_SOURCE" ]]; then
        AUDIO_ARGS=(--audio="$DESKTOP_SOURCE")
    elif [[ -n "$MIC_SOURCE" ]]; then
        AUDIO_ARGS=(--audio="$MIC_SOURCE")
    fi

    FILENAME="recording_$(getdate).mp4"
    printf '%s' "$RECORDING_DIR/$FILENAME" > "$STATE_FILE"

    # No body: there is nothing to copy yet, and an empty body is what makes the
    # shell drop the copy button. The path shows up in the stop notification.
    notify-send "Starting recording" -a 'Recorder' & disown

    trap unloadaudiomodules EXIT
    wf-recorder "${AREA_ARGS[@]}" --pixel-format yuv420p -f "./$FILENAME" -t "${AUDIO_ARGS[@]}"
fi
