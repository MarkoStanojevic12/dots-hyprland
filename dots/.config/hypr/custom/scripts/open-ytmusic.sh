#!/usr/bin/env bash
# Opens YouTube Music as a dedicated Chrome app window, then starts playback.
#
# Workspace placement (ws8) is handled declaratively by a window rule in
# ~/.config/hypr/custom/rules.lua matching the chrome-music.youtube.com class.
# That works whether or not Chrome is already running, unlike a [workspace ...]
# exec rule (which only applies when the launched PID owns the new window).
#
# Called by the bar's media widget (modules/ii/bar/Media.qml) when nothing is playing.
set -u

# watch?list=LM = a watch session seeded from your Liked Music, so a track is
# actually loaded and playback can start (a bare music.youtube.com home page has
# nothing queued, so it would never auto-play). Requires being logged in.
google-chrome-stable --app="https://music.youtube.com/watch?list=LM" --autoplay-policy=no-user-gesture-required &

# Wait for the YouTube Music MPRIS player to register, then press play.
# (Starting playback this way works regardless of Chrome's autoplay policy.)
command -v playerctl >/dev/null 2>&1 || exit 0
for _ in $(seq 1 100); do   # up to ~20s for the page to load
    player=$(playerctl -l 2>/dev/null | grep -im1 chromium)
    if [ -n "$player" ]; then
        sleep 1   # let the page restore its queue before we hit play
        playerctl -p "$player" play 2>/dev/null
        exit 0
    fi
    sleep 0.2
done
