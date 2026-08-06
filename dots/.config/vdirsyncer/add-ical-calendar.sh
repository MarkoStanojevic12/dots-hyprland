#!/usr/bin/env bash
# Add a calendar by iCal (.ics) URL -- for calendars Google's CalDAV endpoint
# refuses to expose, i.e. anything shared to you from another account, which
# lands under "Other calendars".
#
#   bash ~/.config/vdirsyncer/add-ical-calendar.sh work 'https://calendar.google.com/calendar/ical/.../basic.ics' '#4DB6AC'
#
# Get the URL from the account that OWNS the calendar:
#   Google Calendar -> that calendar's Settings -> Integrate calendar
#   -> "Secret address in iCal format"
#
# Read-only by nature, which suits the sidebar. Safe to re-run.
set -uo pipefail

NAME="${1:-}"
URL="${2:-}"
COLOR="${3:-}"

CONFIG="$HOME/.config/vdirsyncer/config"
KHAL="$HOME/.config/khal/config"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[31m  ✗\033[0m %s\n' "$*"; exit 1; }

if [[ -z "$NAME" || -z "$URL" ]]; then
    cat <<EOF

  Usage: bash $0 <name> <ics-url> [colour]

    name    local label, e.g. work   (letters, digits, underscores)
    ics-url the calendar's "Secret address in iCal format"
    colour  optional #RRGGBB for the dot/stripe (default teal)

  Get the URL from the account that owns the calendar:
    Google Calendar -> calendar settings -> Integrate calendar
    -> "Secret address in iCal format"

  Quote the URL -- it contains characters the shell would otherwise eat.

EOF
    exit 1
fi

[[ "$NAME" =~ ^[a-zA-Z0-9_]+$ ]] || die "Name must be letters, digits and underscores only."
[[ "$URL" =~ ^https?:// ]] || die "That does not look like a URL."
[[ -z "$COLOR" ]] && COLOR="#4DB6AC"
[[ "$COLOR" =~ ^#[0-9a-fA-F]{6}$ ]] || die "Colour must be #RRGGBB, e.g. #4DB6AC"

PAIR="${NAME}_ical"
CALDIR="$HOME/.local/share/vdirsyncer/calendars-${NAME}-ical/${NAME}"

echo
bold "── Adding iCal calendar '${NAME}' ─────────────────────────────"

command -v vdirsyncer &>/dev/null || die "vdirsyncer is not installed."
[[ -f "$CONFIG" ]] || die "No $CONFIG. Run setup-google.sh first."

# --------------------------------------------------- validate before wiring in
# Google's two iCal addresses differ only in one path segment:
#   secret: .../ical/<id>/private-<hash>/basic.ics
#   public: .../ical/<id>/public/basic.ics
# The public one 404s unless the calendar is genuinely public, which a work
# calendar will not be. Catch it before wasting a request.
if [[ "$URL" == *"/public/basic.ics"* || "$URL" == *"/public/full.ics"* ]]; then
    echo
    warn "That is the PUBLIC iCal address (its path contains /public/)."
    echo
    echo "  It only works if the calendar is published to the world, which a"
    echo "  work calendar will not be -- hence the 404."
    echo
    echo "  You want the one just below it, whose path contains /private-...:"
    echo "    https://calendar.google.com/calendar/ical/<id>/private-<hash>/basic.ics"
    echo
    echo "  In Integrate calendar, that field is labelled"
    echo "  \"Secret address in iCal format\". You may need to click the eye/copy"
    echo "  icon to reveal it first."
    echo
    die "Re-run with the secret address."
fi

echo "  Checking the feed..."
tmp=$(mktemp)
hdr=$(mktemp)
trap 'rm -f "$tmp" "$hdr"' EXIT
code=$(curl -sSL --max-time 45 -D "$hdr" -o "$tmp" -w '%{http_code}' "$URL" 2>/dev/null || echo "000")
if [[ "$code" != "200" ]]; then
    echo
    warn "The server answered HTTP ${code}."
    echo
    case "$code" in
        404)
            echo "  404 means Google does not recognise that address. Usually one of:"
            echo "    - it is the public address for a non-public calendar"
            echo "    - the secret address was reset (Google invalidates the old one)"
            echo "    - the URL got truncated when copied"
            echo
            echo "  Re-copy \"Secret address in iCal format\" with the copy button,"
            echo "  from the account that OWNS the calendar."
            ;;
        401|403)
            echo "  Your Workspace admin may have disabled secret/external iCal"
            echo "  addresses. That is a separate policy from calendar sharing."
            echo "  If so, the OAuth route is the way in:"
            echo "    bash ~/.config/vdirsyncer/add-google-account.sh work"
            ;;
        000)
            echo "  No response at all -- network, DNS or proxy problem."
            ;;
    esac
    echo
    die "Could not fetch that URL."
fi

if ! grep -q "BEGIN:VCALENDAR" "$tmp"; then
    ctype=$(grep -i '^content-type:' "$hdr" | tail -1 | tr -d '\r')
    echo
    warn "That URL fetched fine, but it is not an iCalendar feed."
    echo
    echo "  It returned: ${ctype:-unknown content type}"
    echo "  First 200 characters:"
    head -c 200 "$tmp" | sed 's/^/    /'
    echo
    echo
    echo "  The address you want ends in .ics and looks like:"
    echo "    https://calendar.google.com/calendar/ical/<long-id>/private-<hash>/basic.ics"
    echo
    echo "  In Google Calendar, on the account that OWNS the calendar:"
    echo "    Settings -> (pick the calendar in the left sidebar, under Settings"
    echo "    for my calendars) -> Integrate calendar"
    echo
    echo "  That section lists several things. You want:"
    echo "    ✓ \"Secret address in iCal format\"   (ends .ics -- this one)"
    echo "    ✗ \"Public address in iCal format\"   (only works if the calendar is public)"
    echo "    ✗ \"Embed code\" / \"Public URL to this calendar\"  (HTML, not a feed)"
    echo
    echo "  Click the copy button next to the secret address rather than"
    echo "  selecting the text, which is easy to truncate."
    echo
    die "Re-run with the .ics address."
fi
nev=$(grep -c "^BEGIN:VEVENT" "$tmp" || true)
ok "Feed is valid iCalendar, ${nev} event(s)"
if [[ "$nev" -eq 0 ]]; then
    warn "The feed has no events. It will sync, but show nothing."
fi

# ---------------------------------------------------------------- vdirsyncer
if grep -q "^\[pair ${PAIR}\]" "$CONFIG"; then
    ok "vdirsyncer already has a '${PAIR}' pair"
else
    cp "$CONFIG" "$CONFIG.bak.$(date +%s)"
    cat >> "$CONFIG" <<EOF

# ---------------------------------------------------------------------------
# iCal feed: ${NAME}
# Google's CalDAV endpoint does not expose calendars shared from another
# account, so this one is pulled from its iCal URL instead. Read-only.
# collections = null because an iCal feed is a single calendar, not a
# discoverable set.
# ---------------------------------------------------------------------------

[pair ${PAIR}]
a = "${NAME}_ical_local"
b = "${NAME}_ical_remote"
collections = null
conflict_resolution = "b wins"

[storage ${NAME}_ical_local]
type = "filesystem"
path = "~/.local/share/vdirsyncer/calendars-${NAME}-ical/${NAME}/"
fileext = ".ics"

[storage ${NAME}_ical_remote]
type = "http"
url = "${URL}"
EOF
    ok "Added pair '${PAIR}' to $CONFIG"
fi

# ---------------------------------------------------------------------- khal
if grep -q "calendars-${NAME}-ical" "$KHAL"; then
    ok "khal already reads this calendar"
else
    cp "$KHAL" "$KHAL.bak.$(date +%s)"
    python3 - "$KHAL" "$NAME" "$COLOR" <<'PY'
import sys
path, name, color = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
# type = calendar, not discover: an iCal feed is one calendar, and an http
# storage carries no displayname/colour metadata, so the colour is set here.
block = f"""
[[{name}]]
path = ~/.local/share/vdirsyncer/calendars-{name}-ical/{name}
type = calendar
color = '{color}'
"""
marker = "\n[locale]"
text = text.replace(marker, block + marker, 1) if marker in text else text.rstrip() + "\n" + block
open(path, "w").write(text)
PY
    ok "Added '${NAME}' to khal with colour ${COLOR}"
fi

mkdir -p "$CALDIR"

# ----------------------------------------------------------- discover + sync
echo
bold "── Sync ───────────────────────────────────────────────────────"
yes y | vdirsyncer discover "${PAIR}" >/dev/null 2>&1 || true
vdirsyncer sync "${PAIR}" || die "Sync failed. Try: vdirsyncer -vdebug sync ${PAIR}"

events=$(find "$CALDIR" -name '*.ics' 2>/dev/null | wc -l)
ok "Synced ${events} event file(s) into ${CALDIR}"

echo
bold "── Done ───────────────────────────────────────────────────────"
echo
echo "  khal now sees:"
khal printcalendars 2>/dev/null | sed 's/^/    /'
echo
echo "  The existing vdirsyncer.timer syncs every pair, so this stays current."
echo "  Note: Google refreshes secret iCal feeds on its own schedule, so new"
echo "  events can take a few hours to appear -- unlike the CalDAV calendars,"
echo "  which update within the 15-minute sync."
echo
