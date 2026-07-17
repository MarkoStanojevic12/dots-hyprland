-- Send the YouTube Music Chrome app window to workspace 8 (opened in the
-- background; remove "silent" to switch there when it opens). Matching by class
-- works regardless of whether Chrome was already running, unlike an exec rule.
-- Chrome derives the app class from the URL path, so the home page is
-- "...__-Default" but the /watch session is "...__watch-Default". Match either.
-- NOTE: class matching here is FULL-match, so the pattern must be anchored end to
-- end (a bare prefix is silently ignored) -- hence the explicit .*$.
hl.window_rule({match = {class = "^chrome-music\\.youtube\\.com__.*$"}, workspace = "8 silent"})
