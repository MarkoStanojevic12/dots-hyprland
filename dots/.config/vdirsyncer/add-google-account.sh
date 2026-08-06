#!/usr/bin/env bash
# Add a second (or third...) Google account to the sidebar calendar.
#
#   bash ~/.config/vdirsyncer/add-google-account.sh work
#
# Each account gets its own vdirsyncer pair, its own local vdir directory and
# its own OAuth token, but reuses the OAuth client from setup-google.sh.
# Safe to re-run: config edits are skipped if already present.
set -uo pipefail

NAME="${1:-}"
CONFIG="$HOME/.config/vdirsyncer/config"
KHAL="$HOME/.config/khal/config"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[31m  ✗\033[0m %s\n' "$*"; exit 1; }

if [[ -z "$NAME" ]]; then
    echo
    echo "  Usage: bash $0 <name>"
    echo "  e.g.:  bash $0 work"
    echo
    echo "  <name> is just a local label. Use letters, digits and underscores."
    exit 1
fi
[[ "$NAME" =~ ^[a-zA-Z0-9_]+$ ]] || die "Name must be letters, digits and underscores only."
[[ "$NAME" == "google" || "$NAME" == "gcal" ]] && die "That name is reserved for the first account."

PAIR="${NAME}_calendar"
CALDIR="$HOME/.local/share/vdirsyncer/calendars-${NAME}"

echo
bold "── Adding Google account '${NAME}' ────────────────────────────"

command -v vdirsyncer &>/dev/null || die "vdirsyncer is not installed. Run setup-google.sh first."
[[ -f "$CONFIG" ]] || die "No $CONFIG. Run setup-google.sh first."

CLIENT_ID=$(grep -m1 -oP '(?<=^client_id = ")[^"]+' "$CONFIG" || true)
CLIENT_SECRET=$(grep -m1 -oP '(?<=^client_secret = ")[^"]+' "$CONFIG" || true)
[[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]] && die "Could not read the OAuth client from $CONFIG. Run setup-google.sh first."
ok "Reusing the existing OAuth client"

# ---------------------------------------------------------------- vdirsyncer
if grep -q "^\[pair ${PAIR}\]" "$CONFIG"; then
    ok "vdirsyncer already has a '${PAIR}' pair"
else
    cp "$CONFIG" "$CONFIG.bak.$(date +%s)"
    cat >> "$CONFIG" <<EOF

# ---------------------------------------------------------------------------
# Additional Google account: ${NAME}
# ---------------------------------------------------------------------------

[pair ${PAIR}]
a = "${NAME}_local"
b = "${NAME}_remote"
collections = ["from b"]
metadata = ["displayname", "color"]
conflict_resolution = "b wins"

[storage ${NAME}_local]
type = "filesystem"
path = "~/.local/share/vdirsyncer/calendars-${NAME}/"
fileext = ".ics"

[storage ${NAME}_remote]
type = "google_calendar"
token_file = "~/.local/share/vdirsyncer/google_token_${NAME}"
read_only = true
client_id = "${CLIENT_ID}"
client_secret = "${CLIENT_SECRET}"
EOF
    ok "Added pair '${PAIR}' to $CONFIG"
fi

# ---------------------------------------------------------------------- khal
if grep -q "calendars-${NAME}" "$KHAL"; then
    ok "khal already reads calendars-${NAME}"
else
    cp "$KHAL" "$KHAL.bak.$(date +%s)"
    # Insert after the existing [calendars] entries, before [locale].
    python3 - "$KHAL" "$NAME" <<'PY'
import sys
path, name = sys.argv[1], sys.argv[2]
text = open(path).read()
block = f"""
[[{name}]]
path = ~/.local/share/vdirsyncer/calendars-{name}/*
type = discover
color = auto
"""
marker = "\n[locale]"
if marker in text:
    text = text.replace(marker, block + marker, 1)
else:
    text = text.rstrip() + "\n" + block
open(path, "w").write(text)
PY
    ok "Added calendars-${NAME} to khal"
fi

mkdir -p "$CALDIR"

# ------------------------------------------------------------------ discover
echo
bold "── Authorise the '${NAME}' account ────────────────────────────"
cat <<EOF

  A browser window will open. Sign in with the ${NAME} account -- NOT your
  personal one. Two things commonly bite here:

  1. Your OAuth consent screen is in "Testing" mode, so the ${NAME} address
     must be added as a Test user first:
       APIs & Services -> OAuth consent screen -> Audience -> Add users

  2. If ${NAME} is a Google Workspace account, its administrator may block
     unverified third-party apps. If authorisation fails with "access blocked"
     or discovery fails with 403, an admin has to allow this OAuth client:
       ${CLIENT_ID}

  When vdirsyncer asks whether to create collections, answer: y

EOF
read -rp "  Press Enter to continue... " _
echo

if ! vdirsyncer discover "${PAIR}"; then
    echo
    warn "Discovery failed. Digging out the real reason..."
    reason=$(vdirsyncer -vdebug discover "${PAIR}" </dev/null 2>&1 \
        | grep -oP '(?<=<internalReason>).*(?=</internalReason>)' | head -1)
    if [[ -n "$reason" ]]; then
        echo
        echo "  Google says:"
        echo "    $reason"
    fi
    echo
    die "Fix the above, then re-run this script."
fi
ok "Calendars discovered"

echo
bold "── Sync ───────────────────────────────────────────────────────"
vdirsyncer metasync "${PAIR}" || warn "metasync had problems (names/colours may be missing)"
vdirsyncer sync "${PAIR}"     || die "Sync failed."

count=$(find "$CALDIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
events=$(find "$CALDIR" -name '*.ics' 2>/dev/null | wc -l)
ok "Synced $count calendar(s), $events event file(s)"

echo
bold "── Done ───────────────────────────────────────────────────────"
echo
echo "  The existing vdirsyncer.timer already syncs every pair, so this"
echo "  account is now kept up to date too -- nothing else to enable."
echo
echo "  New calendars:"
find "$CALDIR" -mindepth 1 -maxdepth 1 -type d -printf '    - %f\n' 2>/dev/null
echo
echo "  khal now sees:"
khal printcalendars 2>/dev/null | sed 's/^/    /'
echo
echo "  Open the right sidebar -- the new events should appear in the Week tab,"
echo "  colour-coded, with the legend at the bottom listing every calendar."
echo
