# Hooking the Hyprland sidebar calendar up to Google Calendar

Data path:

```
Google Calendar  --(vdirsyncer, OAuth)-->  ~/.local/share/vdirsyncer/calendars/*/*.ics
                 --(khal --json)-------->  Quickshell services/CalendarEvents.qml
                 ------------------------>  right sidebar: Week tab + Month tab
```

## What you get

**Week tab** (the main one): the next seven days *starting with today*, each
with its events listed inline. It is a rolling window, not a Monday-aligned
calendar week — days that have already passed are wasted rows. Today is the
first entry and is highlighted.

- Clicking an event opens its meeting link. Google Meet, Zoom, Teams, Jitsi,
  Whereby, Webex and a few others are recognised and get a camera icon;
  anything else with a link gets an "open" icon. Google puts the Meet URL in
  the event *description*, not the ICS `URL` field, so the description is
  scanned for it.
- Cancelled events are struck through, recurring ones get a repeat icon.
- Arrows (or PageUp/PageDown) page the window forward and back a week at a
  time; a "today" button appears whenever you have navigated away. The circular
  arrow forces an immediate vdirsyncer sync instead of waiting for the
  15-minute timer.
- Want more or fewer than seven days? `calendar.events.daysShown` in
  `~/.config/illogical-impulse/config.json`.
- When you have more than one calendar, a colour legend appears at the bottom.

**Month tab**: the month grid, with coloured dots under any day that has
events — one dot per calendar. Clicking a day jumps the Week tab to that week.

Panel too short or too tall? `sidebar.bottomGroupHeight` in
`~/.config/illogical-impulse/config.json` (default 560).

## 1. Install

```fish
sudo pacman -S --needed vdirsyncer python-aiohttp-oauthlib khal
```

`python-aiohttp-oauthlib` is what gives vdirsyncer its `google_calendar`
storage type — without it you get "unknown storage type".

## 2. Create a Google OAuth client

Google requires *your own* OAuth client for CalDAV-style access; there is no
shared one.

1. <https://console.cloud.google.com/> → create a project (any name).
2. **APIs & Services → Library** → enable **CalDAV API**.
   This is the one that matters — vdirsyncer talks CalDAV, not the REST API.
   Enabling "Google Calendar API" instead is a very easy mistake to make and
   fails in a thoroughly unhelpful way: discovery dies with `Not Found`,
   because vdirsyncer falls back to `/.well-known/caldav` (a genuine 404) and
   reports that instead of Google's actual complaint. Run
   `vdirsyncer -vdebug discover google_calendar` and the real message is in
   there: "CalDAV API has not been used in project ... before or it is
   disabled."
3. **APIs & Services → OAuth consent screen**:
   - User type **External**, fill in the required name/email fields.
   - Under **Audience**, add your own Gmail address as a **Test user**.
     (Leave the app in "Testing" — publishing it is unnecessary for personal
     use. Testing-mode refresh tokens expire after 7 days *only* for apps
     using sensitive scopes without verification; if you hit weekly
     re-authentication, publish the app to fix it.)
4. **APIs & Services → Credentials → Create credentials → OAuth client ID**
   - Application type: **Desktop app**.
5. Copy the client ID and client secret.

## 3. Fill them in

Edit `~/.config/vdirsyncer/config` and replace:

- `YOUR_CLIENT_ID_HERE.apps.googleusercontent.com`
- `YOUR_CLIENT_SECRET_HERE`

## 4. First sync (interactive — opens a browser)

```fish
vdirsyncer discover google_calendar
```

Say `y` when it asks to create the local collections. This is where every
calendar on your account gets picked up, including shared ones. Then:

```fish
vdirsyncer metasync
vdirsyncer sync
```

Verify:

```fish
ls ~/.local/share/vdirsyncer/calendars/
khal list today 7d
```

## 5. Automatic syncing

```fish
systemctl --user daemon-reload
systemctl --user enable --now vdirsyncer.timer
systemctl --user list-timers vdirsyncer.timer
```

Force a sync any time with `systemctl --user start vdirsyncer.service`, or
from the sidebar's Agenda tab refresh button.

## Notes

- The remote storage is `read_only = true`, so nothing is ever written back to
  Google. Flip it to `false` in `~/.config/vdirsyncer/config` if you later want
  two-way sync.
- Adding a *new* calendar in Google later needs one `vdirsyncer discover
  google_calendar` run to pick it up; ordinary event changes do not.
- Adding a whole *second Google account* (a work/Workspace one, say):

      bash ~/.config/vdirsyncer/add-google-account.sh work

  It reuses the same OAuth client but gives the account its own pair, its own
  vdir directory and its own token. The existing `vdirsyncer.timer` syncs every
  pair, so nothing extra needs enabling. Two gotchas: while the consent screen
  is in "Testing" the new address must be added as a Test user, and a Workspace
  admin can block unverified third-party apps outright — that shows up as
  "access blocked" at sign-in or a 403 during discovery, and only an admin can
  allow the client ID.

  **Sharing a calendar to your personal account does NOT work.** It is the
  obvious-looking shortcut and it is a dead end: Google's CalDAV endpoint only
  exposes calendars you own ("My calendars"). Calendars shared to you land
  under "Other calendars" and are invisible over CalDAV no matter what
  permission level was granted — even "See all event details". They show up in
  the Google Calendar web UI because that uses the REST API, which has no such
  restriction. Verified by querying the CalDAV `calendar-home-set` directly: it
  returned only the four owned calendars.

- For a calendar you cannot reach over CalDAV, pull its iCal feed instead:

      bash ~/.config/vdirsyncer/add-ical-calendar.sh work '<secret .ics url>' '#4DB6AC'

  Get the URL from the account that *owns* the calendar: Google Calendar ->
  calendar settings -> Integrate calendar -> **Secret address in iCal format**
  (path contains `/private-...`; the public address next to it contains
  `/public/` and 404s unless the calendar is world-readable). An iCal feed
  carries no colour metadata, hence the colour argument. Caveat: Google
  refreshes these feeds on its own schedule, so new events can lag by hours,
  unlike the CalDAV calendars which are current within the 15-minute sync.
- The OAuth refresh token lives in `~/.local/share/vdirsyncer/google_token`.
  Delete it to force re-authentication.

- **Leaving the app in "Testing" expires the refresh token every 7 days.**
  That is a Google policy for apps with Testing publishing status, and it fails
  quietly: vdirsyncer starts erroring, khal keeps serving the last synced data,
  and the sidebar shows stale events with no visible complaint. Fix it once:

      Google Cloud console -> APIs & Services -> OAuth consent screen
      -> Publishing status -> Publish app  ("In production")

  Production apps do not get the 7-day expiry. The "unverified app" warning at
  sign-in stays, which is harmless for personal use; verification is only
  needed to remove that warning or exceed 100 users.

  To check the current window:

      python3 -c "import json,os;t=json.load(open(os.path.expanduser('~/.local/share/vdirsyncer/google_token')));print(round(t['refresh_token_expires_in']/86400,1),'days')"

  If it has already lapsed, re-run `setup-google.sh`; the saved credentials
  mean it goes straight to the browser step.

- Calendars pulled from an iCal URL have no token and are immune to all of the
  above — worth remembering when only some calendars go stale.
