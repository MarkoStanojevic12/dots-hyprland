#!/usr/bin/env bash
# Guided setup for Google Calendar -> vdirsyncer -> khal -> Hyprland sidebar.
# Safe to re-run; it skips whatever is already done.
set -uo pipefail

CONFIG="$HOME/.config/vdirsyncer/config"
TOKEN="$HOME/.local/share/vdirsyncer/google_token"
CALDIR="$HOME/.local/share/vdirsyncer/calendars"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[31m  ✗\033[0m %s\n' "$*"; exit 1; }

echo
bold "── Step 1/5: packages ─────────────────────────────────────────"

missing=()
for p in vdirsyncer python-aiohttp-oauthlib khal; do
    pacman -Q "$p" &>/dev/null || missing+=("$p")
done

if (( ${#missing[@]} > 0 )); then
    warn "Missing: ${missing[*]}"
    echo

    # A stale sync db makes pacman request package versions that mirrors have
    # already dropped, so every mirror 404s. Catch that before it wastes a run.
    newest_db=$(find /var/lib/pacman/sync -name '*.db' -printf '%T@\n' 2>/dev/null | sort -rn | head -1)
    if [[ -n "$newest_db" ]]; then
        age_days=$(( ( $(date +%s) - ${newest_db%.*} ) / 86400 ))
        if (( age_days > 3 )); then
            warn "Your pacman database is ${age_days} days old."
            echo "  Installing without refreshing it first will fail with 404s"
            echo "  on every mirror. Upgrade first:"
            echo
            echo "      sudo pacman -Syu"
            echo
            echo "  then:"
            echo
            echo "      sudo pacman -S --needed ${missing[*]}"
            echo
            echo "  (Do not use 'pacman -Sy <pkg>' to skip the upgrade -- that"
            echo "   creates a partial upgrade and can break the system.)"
            echo
            exit 1
        fi
    fi

    echo "  Run this, then start this script again:"
    echo
    echo "      sudo pacman -S --needed ${missing[*]}"
    echo
    exit 1
fi
ok "vdirsyncer, khal and the Google OAuth support are installed"

echo
bold "── Step 2/5: Google OAuth client ──────────────────────────────"

if grep -q "YOUR_CLIENT_ID_HERE" "$CONFIG"; then
    cat <<'EOF'

  Google needs you to create your own OAuth client. It is free and takes
  about two minutes. In the browser window that opens:

    1. Create a project (any name will do).
    2. APIs & Services -> Library -> search "CalDAV API" -> Enable.
       NOT "Google Calendar API" -- vdirsyncer speaks CalDAV. Picking the
       wrong one fails later with a misleading "Not Found".
    3. APIs & Services -> OAuth consent screen:
         - User type: External
         - Fill in app name + your email where required
         - Under Audience, add your own Gmail address as a Test user
    4. APIs & Services -> Credentials -> Create credentials
         -> OAuth client ID -> Application type: Desktop app -> Create
    5. Copy the Client ID and Client secret it shows you.

EOF
    read -rp "  Press Enter to open the Google Cloud console... " _
    (xdg-open "https://console.cloud.google.com/projectcreate" &>/dev/null &)
    echo
    read -rp "  Paste your Client ID:     " CLIENT_ID
    read -rp "  Paste your Client secret: " CLIENT_SECRET

    [[ -z "${CLIENT_ID// }"     ]] && die "Client ID was empty."
    [[ -z "${CLIENT_SECRET// }" ]] && die "Client secret was empty."

    cp "$CONFIG" "$CONFIG.bak.$(date +%s)"
    # '|' as the sed delimiter: client IDs contain '/' and '.'
    sed -i "s|YOUR_CLIENT_ID_HERE.apps.googleusercontent.com|${CLIENT_ID}|" "$CONFIG"
    sed -i "s|YOUR_CLIENT_SECRET_HERE|${CLIENT_SECRET}|" "$CONFIG"
    grep -q "YOUR_CLIENT_ID_HERE\|YOUR_CLIENT_SECRET_HERE" "$CONFIG" \
        && die "Could not write the credentials into $CONFIG -- edit it by hand."
    ok "Credentials written to $CONFIG"
else
    ok "Credentials already present in $CONFIG"
fi

echo
bold "── Step 3/5: authorise and discover your calendars ────────────"
echo
echo "  A browser window will ask you to sign in and grant calendar access."
echo "  Google will warn the app is unverified -- that is expected, it is"
echo "  your own client. Choose Advanced -> Go to (your app name)."
echo
echo "  When vdirsyncer asks whether to create collections, answer: y"
echo
read -rp "  Press Enter to continue... " _
echo

if ! vdirsyncer discover google_calendar; then
    echo
    warn "Discovery failed. Digging out the real reason..."
    # vdirsyncer surfaces the last error it hit, which is usually the harmless
    # /.well-known/caldav 404 rather than what Google actually objected to.
    # Google's real complaint is in the response body, visible only under -vdebug.
    reason=$(vdirsyncer -vdebug discover google_calendar </dev/null 2>&1 \
        | grep -oP '(?<=<internalReason>).*(?=</internalReason>)' | head -1)
    if [[ -n "$reason" ]]; then
        echo
        echo "  Google says:"
        echo "    $reason"
    else
        echo
        echo "  No specific reason from Google. Full traceback:"
        echo "      vdirsyncer -vdebug discover google_calendar"
    fi
    echo
    die "Fix the above, then re-run this script."
fi
ok "Calendars discovered"

echo
bold "── Step 4/5: first sync ───────────────────────────────────────"
vdirsyncer metasync || warn "metasync had problems (names/colours may be missing)"
vdirsyncer sync     || die "Sync failed."

count=$(find "$CALDIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
events=$(find "$CALDIR" -name '*.ics' 2>/dev/null | wc -l)
ok "Synced $count calendar(s), $events event file(s)"

echo
bold "── Step 5/5: keep it in sync automatically ────────────────────"
systemctl --user daemon-reload
systemctl --user enable --now vdirsyncer.timer || die "Could not enable vdirsyncer.timer"
ok "vdirsyncer.timer enabled (syncs every 15 minutes)"

echo
bold "── Done ───────────────────────────────────────────────────────"
echo
echo "  Your calendars:"
khal calendar 2>/dev/null >/dev/null && \
    find "$CALDIR" -mindepth 1 -maxdepth 1 -type d -printf '    - %f\n' 2>/dev/null
echo
echo "  Next 7 days:"
khal list today 7d 2>&1 | sed 's/^/    /' | head -30
echo
echo "  Open the right sidebar -- the Agenda tab should now show these,"
echo "  and days with events get coloured dots in the month grid."
echo
