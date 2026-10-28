pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick
import "linkIcons.js" as LinkIcons

/**
 * What the links in a Claude reply are: the site behind each one, the icon and
 * short name it is drawn with, and for tickets, PRs, issues and crashes the
 * live state their cards show.
 *
 * Work sites, repo nicknames and Jira project keys come from link-rules.json in
 * the shell config dir, which the public dotfiles never carry; without it every
 * link still gets its brand icon and a generic name.
 */
Singleton {
    id: root

    // [icon, name, host patterns]. An icon is a Simple Icons slug or ms:<symbol>.
    // "*.x" is x and its subdomains, "x.*" a prefix, and a /path narrows the rule;
    // the longest matching pattern wins.
    readonly property var builtinRules: [
        ["jira", "Jira", "*.atlassian.net/browse *.atlassian.net/jira"],
        ["confluence", "Confluence", "*.atlassian.net/wiki"],
        ["atlassian", "Atlassian", "*.atlassian.net atlassian.com id.atlassian.com"],
        ["github", "GitHub", "github.com gist.github.com raw.githubusercontent.com docs.github.com"],
        ["githubactions", "GitHub Actions", "github.com/*/*/actions"],
        ["sentry", "Sentry", "*.sentry.io"],
        ["figma", "Figma", "*.figma.com"],
        ["claude", "Claude", "claude.ai claude.com docs.claude.com"],
        ["anthropic", "Anthropic", "*.anthropic.com"],
        ["gitkraken", "GitKraken", "*.gitkraken.com"],
        ["trello", "Trello", "trello.com"],
        ["notion", "Notion", "notion.so *.notion.site"],
        ["qt", "Qt", "*.qt.io"],
        ["stackoverflow", "Stack Overflow", "stackoverflow.com"],
        ["stackexchange", "Stack Exchange", "*.stackexchange.com"],
        ["superuser", "Super User", "superuser.com"],
        ["serverfault", "Server Fault", "serverfault.com"],
        ["mdnwebdocs", "MDN", "developer.mozilla.org"],
        ["gitlab", "GitLab", "*.gitlab.com *.gitlab.io"],
        ["codeberg", "Codeberg", "codeberg.org"],
        ["gitea", "Gitea", "gitea.com"],
        ["bitbucket", "Bitbucket", "bitbucket.org"],
        ["npm", "npm", "*.npmjs.com"],
        ["pnpm", "pnpm", "pnpm.io"],
        ["nodedotjs", "Node.js", "nodejs.org"],
        ["typescript", "TypeScript", "typescriptlang.org"],
        ["react", "React", "react.dev reactnative.dev"],
        ["expo", "Expo", "*.expo.dev"],
        ["python", "Python", "*.python.org"],
        ["pypi", "PyPI", "pypi.org"],
        ["rust", "Rust", "*.rust-lang.org docs.rs crates.io"],
        ["cmake", "CMake", "cmake.org"],
        ["kotlin", "Kotlin", "kotlinlang.org"],
        ["gradle", "Gradle", "*.gradle.org"],
        ["docker", "Docker", "*.docker.com"],
        ["mongodb", "MongoDB", "*.mongodb.com"],
        ["sqlite", "SQLite", "sqlite.org"],
        ["postman", "Postman", "*.postman.com"],
        ["swagger", "Swagger", "swagger.io"],
        ["firebase", "Firebase", "firebase.google.com console.firebase.google.com"],
        ["cloudflare", "Cloudflare", "*.cloudflare.com"],
        ["digitalocean", "DigitalOcean", "*.digitalocean.com"],
        ["jetbrains", "JetBrains", "*.jetbrains.com"],
        ["readthedocs", "Read the Docs", "*.readthedocs.io"],
        ["apple", "Apple", "*.apple.com ipsw.me appledb.dev theapplewiki.com"],
        ["appstore", "App Store", "apps.apple.com"],
        ["xcode", "Xcode", "developer.apple.com/xcode"],
        ["swift", "Swift", "swift.org"],
        ["icloud", "iCloud", "icloud.com"],
        ["ms:phone_iphone", "libimobiledevice", "libimobiledevice.org"],
        ["android", "Android", "*.android.com"],
        ["androidstudio", "Android Studio", "developer.android.com/studio"],
        ["googleplay", "Google Play", "play.google.com"],
        ["samsung", "Samsung", "*.samsung.com"],
        ["xiaomi", "Xiaomi", "mi.com xiaomi.com"],
        ["huawei", "Huawei", "*.huawei.com"],
        ["lineageos", "LineageOS", "*.lineageos.org"],
        ["fdroid", "F-Droid", "f-droid.org"],
        ["xdadevelopers", "XDA", "xda-developers.com"],
        ["ifixit", "iFixit", "*.ifixit.com"],
        ["archlinux", "Arch Linux", "*.archlinux.org"],
        ["cachyos", "CachyOS", "*.cachyos.org"],
        ["ubuntu", "Ubuntu", "*.ubuntu.com askubuntu.com launchpad.net"],
        ["debian", "Debian", "*.debian.org"],
        ["fedora", "Fedora", "*.fedoraproject.org"],
        ["kde", "KDE", "*.kde.org"],
        ["gnome", "GNOME", "*.gnome.org"],
        ["hyprland", "Hyprland", "*.hyprland.org *.hypr.land"],
        ["wayland", "Wayland", "wayland.freedesktop.org"],
        ["flathub", "Flathub", "flathub.org"],
        ["flatpak", "Flatpak", "*.flatpak.org"],
        ["linux", "Linux kernel", "*.kernel.org"],
        ["nvidia", "NVIDIA", "*.nvidia.com"],
        ["amd", "AMD", "*.amd.com"],
        ["google", "Google", "*.google.com goo.gl"],
        ["gmail", "Gmail", "mail.google.com"],
        ["googledocs", "Google Docs", "docs.google.com/document"],
        ["googlesheets", "Google Sheets", "docs.google.com/spreadsheets"],
        ["googledrive", "Google Drive", "drive.google.com"],
        ["googlecalendar", "Google Calendar", "calendar.google.com"],
        ["googlemeet", "Google Meet", "meet.google.com"],
        ["googlemaps", "Google Maps", "maps.google.com google.com/maps maps.app.goo.gl"],
        ["googletranslate", "Google Translate", "translate.google.com"],
        ["googlechrome", "Chrome Web Store", "chromewebstore.google.com"],
        ["wikipedia", "Wikipedia", "*.wikipedia.org"],
        ["youtube", "YouTube", "*.youtube.com youtu.be"],
        ["reddit", "Reddit", "*.reddit.com redd.it"],
        ["x", "X", "x.com twitter.com"],
        ["ycombinator", "Hacker News", "news.ycombinator.com"],
        ["discord", "Discord", "discord.com discord.gg"],
        ["telegram", "Telegram", "t.me telegram.org"],
        ["whatsapp", "WhatsApp", "whatsapp.com wa.me"],
        ["signal", "Signal", "signal.org"],
        ["viber", "Viber", "viber.com"],
        ["medium", "Medium", "*.medium.com"],
        ["obsidian", "Obsidian", "*.obsidian.md"],
        ["mozilla", "Mozilla", "*.mozilla.org"],
        ["firefox", "Firefox Add-ons", "addons.mozilla.org"],
        ["duckduckgo", "DuckDuckGo", "duckduckgo.com"],
        ["imdb", "IMDb", "*.imdb.com"],
        ["spotify", "Spotify", "*.spotify.com"],
        ["twitch", "Twitch", "twitch.tv"],
        ["openstreetmap", "OpenStreetMap", "openstreetmap.org"],
        ["steam", "Steam", "*.steampowered.com steamcommunity.com"],
        ["battledotnet", "Battle.net", "*.battle.net *.blizzard.com"],
        ["protondb", "ProtonDB", "protondb.com"],
        ["ms:extension", "Nexus Mods", "*.nexusmods.com"],
        ["paypal", "PayPal", "*.paypal.com"],
        ["revolut", "Revolut", "revolut.com"],
        ["wise", "Wise", "wise.com"],
        ["aliexpress", "AliExpress", "*.aliexpress.com"],
        ["ebay", "eBay", "*.ebay.com"],
        ["airbnb", "Airbnb", "*.airbnb.com"],
        ["tripadvisor", "Tripadvisor", "*.tripadvisor.com"],
        ["ms:delivery_dining", "Wolt", "wolt.com"],
        ["ms:smart_toy", "ChatGPT", "chatgpt.com *.openai.com"],
        ["ms:account_balance", "Government", "*.gov *.gov.rs *.gov.uk *.europa.eu"],
        ["ms:dns", "Local server", "localhost 127.* 10.* 192.168.*"]
    ]

    // Kinds that get a full card when they sit on a line of their own.
    readonly property var richKinds: ["ticket", "pr", "issue", "crash"]

    // Unknown sites get a letter tile, its colours picked from the host.
    readonly property var tilePalettes: [["#643d2d", "#ffd8c9"], ["#4d480e", "#eee5a0"], ["#78310e", "#ffdbcd"], ["#3c332f", "#f0dfd9"], ["#2f4a3a", "#c8ecd2"]]

    property var localRules: ({})
    readonly property var repoShortNames: root.localRules.repoShortNames ?? {}
    // { "ABC": "https://example.atlassian.net" }: a bare ABC-123 in a reply links
    // to that site. Only listed keys count, so UTF-8 or SHA-256 never do.
    readonly property var jiraProjects: root.localRules.jiraProjects ?? {}
    readonly property var ticketKeyTest: {
        const keys = Object.keys(root.jiraProjects).filter(key => /^[A-Z][A-Z0-9]+$/.test(key));
        return keys.length > 0 ? new RegExp(`(?:^|[^\\w/.-])(?:${keys.join("|")})-\\d`) : null;
    }

    readonly property var rules: {
        const out = [];
        const add = (icon, name, patterns, local) => {
            for (const pattern of String(patterns ?? "").split(/\s+/)) {
                if (pattern.length === 0) continue;
                const slash = pattern.indexOf("/");
                const path = slash < 0 ? "" : pattern.slice(slash);
                out.push({
                    icon: root.knownIcon(icon) ? icon : null,
                    name: String(name ?? ""),
                    host: slash < 0 ? pattern : pattern.slice(0, slash),
                    path: path.length === 0 ? null
                        : new RegExp("^" + path.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, "[^/]+") + "(/|$)"),
                    // Local rules win a tie, so a work site can take over a generic one.
                    weight: pattern.length + (local ? 0.5 : 0)
                });
            }
        };
        for (const site of root.localRules.sites ?? []) add(site.icon, site.name, site.hosts, true);
        for (const rule of root.builtinRules) add(rule[0], rule[1], rule[2], false);
        return out;
    }

    // Plain JS caches: mutated in place, so filling them never re-runs a binding.
    readonly property var memo: ({ rules: null, classified: ({}), icons: ({}), links: ({}), asked: ({}), queue: [], running: [] })

    FileView {
        path: `${Directories.shellConfig}/link-rules.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                root.localRules = parsed && typeof parsed === "object" ? parsed : {};
            } catch (e) {
                root.localRules = {};
            }
        }
        onLoadFailed: root.localRules = {}
    }

    function knownIcon(icon) {
        if (typeof icon !== "string") return false;
        if (icon.startsWith("ms:")) return LinkIcons.symbols[icon.slice(3)] !== undefined;
        return LinkIcons.brands[icon] !== undefined;
    }

    function hostMatches(pattern, host) {
        if (pattern.startsWith("*.")) return host === pattern.slice(2) || host.endsWith(pattern.slice(1));
        if (pattern.endsWith(".*")) return host.startsWith(pattern.slice(0, -1));
        return host === pattern;
    }

    function matchRule(host, path) {
        let best = null;
        for (const rule of root.rules) {
            if (best && rule.weight <= best.weight) continue;
            if (root.hostMatches(rule.host, host) && (!rule.path || rule.path.test(path))) best = rule;
        }
        return best;
    }

    function prettyHost(host) {
        const parts = host.split(".");
        const base = parts.length > 2 && parts[parts.length - 2].length <= 3 ? parts[parts.length - 3] : (parts[parts.length - 2] || parts[0]);
        return base.split("-").map(word => word ? word[0].toUpperCase() + word.slice(1) : word).join(" ");
    }

    function truncate(text, length) {
        return text.length > length ? text.slice(0, length - 1).replace(/\s+$/, "") + "…" : text;
    }

    function decode(text) {
        try {
            return decodeURIComponent(text);
        } catch (e) {
            return text;
        }
    }

    function repoShort(repo) {
        return root.repoShortNames[repo] ?? repo;
    }

    // { url, host, site, icon, letter, tile, kind, key, short, ref, repo }, or null
    // for anything that isn't an http(s) link.
    function classify(url) {
        const rules = root.rules;
        if (root.memo.rules !== rules) {
            root.memo.rules = rules;
            root.memo.classified = {};
        }
        const known = root.memo.classified[url];
        if (known !== undefined) return known;

        const parts = String(url).match(/^https?:\/\/(?:[^@\/?#]*@)?([^\/?#:]+)(?::\d+)?([^?#]*)/i);
        if (!parts) return root.memo.classified[url] = null;
        const host = parts[1].toLowerCase().replace(/^www\./, "");
        const path = parts[2] || "/";
        let rule = root.matchRule(host, path);
        if (!rule && /\.pdf$/i.test(path)) rule = { icon: "ms:picture_as_pdf", name: "PDF" };
        const site = rule?.name || root.prettyHost(host);
        const info = {
            url: url, host: host, site: site, icon: rule?.icon ?? null,
            letter: (site.match(/[A-Za-z0-9]/)?.[0] ?? "?").toUpperCase(),
            tile: root.tilePalettes[[...host].reduce((a, c) => (a * 31 + c.charCodeAt(0)) >>> 0, 7) % root.tilePalettes.length],
            kind: "page", key: "", short: site, ref: "", repo: ""
        };

        let m;
        if (host === "github.com" && (m = path.match(/^\/([^/]+)\/([^/]+)(?:\/(pull|issues|commit|blob|tree|actions|releases)(?:\/([^/]+))?)?/))) {
            const repo = `${m[1]}/${m[2]}`;
            const name = root.repoShort(m[2]);
            const number = m[4] ?? "";
            info.repo = repo;
            if (m[3] === "pull" && /^\d+$/.test(number)) {
                Object.assign(info, { kind: "pr", key: `${name} #${number}`, ref: `gh-pr:${repo}#${number}` });
            } else if (m[3] === "issues" && /^\d+$/.test(number)) {
                Object.assign(info, { kind: "issue", key: `${name} #${number}`, ref: `gh-issue:${repo}#${number}` });
            } else if (m[3] === "commit" && number) {
                Object.assign(info, { kind: "code", key: `${name}@${number.slice(0, 7)}` });
            } else if ((m[3] === "blob" || m[3] === "tree") && number) {
                const segments = path.split("/").filter(s => s.length > 0);
                Object.assign(info, { kind: "code", key: `${name}/${root.truncate(root.decode(segments[segments.length - 1]), 28)}` });
            } else if (m[3] === "actions") {
                info.key = `${name} Actions`;
            } else if (m[3] === "releases") {
                info.key = `${name} releases`;
            } else {
                Object.assign(info, { kind: "repo", key: repo });
            }
            info.short = info.key;
        } else if (host.endsWith(".atlassian.net") && (m = path.match(/\/browse\/([A-Z][A-Z0-9]+-\d+)/))) {
            Object.assign(info, { kind: "ticket", key: m[1], short: m[1], ref: `jira:${host}:${m[1]}` });
        } else if (/(^|\.)sentry\.io$/.test(host) && (m = path.match(/\/issues\/(\d+)/))) {
            const org = host !== "sentry.io" ? host.slice(0, -".sentry.io".length) : (path.match(/\/organizations\/([^/]+)\//)?.[1] ?? "");
            Object.assign(info, {
                kind: "crash", key: `Sentry ${m[1]}`, short: `Sentry ${m[1]}`,
                ref: /^[a-z0-9-]+$/.test(org) ? `sentry:${org}:${m[1]}` : ""
            });
        } else {
            const segments = path.split("/").filter(s => s.length > 0);
            let tail = root.decode(segments.length > 0 ? segments[segments.length - 1] : "");
            if (!/^\d+$/.test(tail)) tail = tail.replace(/\.[A-Za-z0-9]{1,5}$/, "").replace(/[-_+]+/g, " ").trim();
            if (tail.length > 0) info.short = `${site} · ${root.truncate(tail, 28)}`;
        }
        return root.memo.classified[url] = info;
    }

    // ------------------------------------------------------------------
    // Icons
    // ------------------------------------------------------------------

    readonly property bool darkTheme: Appearance.m3colors.darkmode
    readonly property string paletteKey: [root.darkTheme, Appearance.colors.colOnLayer1, Appearance.colors.colSecondary].join("|")

    function hexToHsl(hex) {
        const value = parseInt(hex.replace("#", ""), 16);
        const r = ((value >> 16) & 255) / 255, g = ((value >> 8) & 255) / 255, b = (value & 255) / 255;
        const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2;
        if (max === min) return [0, 0, l];
        const d = max - min;
        const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
        const h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
        return [h / 6, s, l];
    }

    function hslToHex(h, s, l) {
        const channel = n => {
            const k = (n + h * 12) % 12;
            const a = s * Math.min(l, 1 - l);
            const c = l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1));
            return Math.round(c * 255).toString(16).padStart(2, "0");
        };
        return `#${channel(0)}${channel(8)}${channel(4)}`;
    }

    // Brand colours made to read on the current theme: near-black and near-white
    // marks take the text colour, and dark brands are lifted on a dark background.
    function brandColor(hex) {
        hex = hex.startsWith("#") ? hex : `#${hex}`;
        const [h, s, l] = root.hexToHsl(hex);
        if (s < 0.18) {
            const faint = root.darkTheme ? l < 0.55 : l > 0.45;
            return faint ? StringUtils.cssColor(Appearance.colors.colOnLayer1) : hex;
        }
        if (root.darkTheme && l < 0.58) return root.hslToHex(h, Math.min(s, 0.85), 0.66);
        if (!root.darkTheme && l > 0.6) return root.hslToHex(h, s, 0.42);
        return hex;
    }

    function iconSvg(info) {
        const open = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">';
        if (info.icon?.startsWith("ms:")) {
            return `${open}<path fill="${StringUtils.cssColor(Appearance.colors.colSecondary)}" d="${LinkIcons.symbols[info.icon.slice(3)]}"/></svg>`;
        }
        if (info.icon) {
            const [hex, d] = LinkIcons.brands[info.icon];
            return `${open}<path fill="${root.brandColor(hex)}" d="${d}"/></svg>`;
        }
        const [dark, light] = info.tile;
        return `${open}<rect width="24" height="24" rx="6" fill="${root.darkTheme ? dark : light}"/>`
            + `<text x="12" y="17.5" font-family="sans-serif" font-size="15" font-weight="bold" text-anchor="middle" fill="${root.darkTheme ? light : dark}">${info.letter}</text></svg>`;
    }

    // A data URI, so one string serves both inline markdown and Image items.
    function iconUri(info) {
        if (!info) return "";
        const key = `${root.paletteKey}|${info.icon ?? `${info.letter}${info.tile[0]}`}`;
        if (root.memo.icons[key] === undefined) root.memo.icons[key] = "data:image/svg+xml;utf8," + encodeURIComponent(root.iconSvg(info));
        return root.memo.icons[key];
    }

    // ------------------------------------------------------------------
    // Prose
    // ------------------------------------------------------------------

    function linkLabel(text) {
        return text.replace(/&/g, "&amp;").replace(/[\[\]`<>]/g, "").replace(/[*_]/g, "\\$&");
    }

    function iconTag(url, px) {
        const info = root.classify(url);
        return info ? `<img src="${root.iconUri(info)}" width="${px}" height="${px}" style="vertical-align: middle"/>&nbsp;` : "";
    }

    // Walks the http(s) links in markdown outside code. Code spans, images and
    // raw HTML tags are matched only so that nothing inside them is touched.
    function ticketUrl(key) {
        const site = root.jiraProjects[key.slice(0, key.lastIndexOf("-"))];
        if (typeof site !== "string" || !/^https?:\/\/[^\s\/]+\/?$/i.test(site)) return null;
        return `${site.replace(/\/+$/, "")}/browse/${key}`;
    }

    function hasLinks(text) {
        return /https?:\/\//i.test(text) || (root.ticketKeyTest?.test(text) ?? false);
    }

    // Calls visit(match, url, label, trailing, isKey) for every link outside code
    // spans, bare ticket keys of listed projects included, and puts back what it
    // returns. A key must stand alone, so a branch like CS-12-fix is no key.
    // The character before a key can't be one that opens a code span, link or
    // tag: Qt's regex engine then sometimes picks the key over the code span
    // around it, and it has no lookbehind to say this another way.
    function eachLink(markdown, visit) {
        return markdown.replace(/(`+)[^\n]*?\1|!\[[^\]\n]*\]\([^)\n]*\)|\[((?:[^\[\]\n]|\[[^\]\n]*\])*)\]\(([^)\s]+)\)|<(https?:\/\/[^>\s]+)>|<\/?[A-Za-z][^>\n]*>|(https?:\/\/[^\s<>()\[\]|`]+(?:\([^\s<>()|`]*\)[^\s<>()\[\]|`]*)*)|(^|[^\w\/.\-`\[<!])([A-Z][A-Z0-9]+-\d+)(?![\w\/-]|\.\w)/gi,
            (match, ticks, label, href, auto, bare, before, key) => {
                if (href !== undefined) return /^https?:\/\//i.test(href) ? visit(match, href, label, "", false) : match;
                if (auto !== undefined) return visit(match, auto, null, "", false);
                if (bare !== undefined) {
                    const url = bare.replace(/[.,;:!?*'"]+$/, "");
                    return visit(match, url, null, bare.slice(url.length), false);
                }
                if (key !== undefined) {
                    const url = root.ticketUrl(key);
                    return url ? before + visit(key, url, null, "", true) : match;
                }
                return match;
            });
    }

    // Whether what was said after a card's link only repeats the card's title,
    // as in "CS-12 (bug): <the ticket's title>". Most of the title has to be in
    // it and little else, so a real note after the title still counts.
    function remarkEchoes(remark, title) {
        const words = text => String(text ?? "").toLowerCase().match(/[a-z0-9À-ɏ]+/g) ?? [];
        const titleWords = new Set(words(title));
        const remarkWords = words(remark);
        if (titleWords.size === 0 || remarkWords.length === 0) return false;
        const said = new Set(remarkWords);
        const covered = [...titleWords].filter(word => said.has(word)).length / titleWords.size;
        const extra = remarkWords.filter(word => !titleWords.has(word)).length / remarkWords.length;
        return covered >= 0.6 && extra <= 0.3;
    }

    // Bare ticket keys as markdown links, so the line parsing below sees links.
    function linkTicketKeys(markdown) {
        return root.eachLink(markdown, (match, url, label, trailing, isKey) => isKey ? `[${match}](${url})` : match);
    }

    // Every link gets its site's icon; a bare URL also gets the short name in
    // place of the raw address. The icon sits in front of the link, never in
    // its label, because inline HTML in a label stops Qt parsing the link.
    function decorate(markdown, px) {
        if (!markdown || !root.hasLinks(markdown)) return markdown ?? "";
        return root.eachLink(markdown, (match, url, label, trailing) => {
            const icon = root.iconTag(url, px);
            if (label !== null) return icon + match;
            const info = root.classify(url);
            return info ? `${icon}[${root.linkLabel(info.short)}](${url})${trailing}` : match;
        });
    }

    // The http(s) links in a reply, in order and without repeats, for the rail.
    function linksIn(id, content) {
        // Read even on a cache hit, so a binding over this re-runs when the rules load.
        const rules = root.rules;
        const cached = root.memo.links[id];
        if (cached && cached.length === content.length && cached.rules === rules) return cached.links;
        const links = [];
        const seen = {};
        for (const block of StringUtils.splitMarkdownBlocks(content)) {
            if (block.type !== "text") continue;
            root.eachLink(block.content, (match, url, label) => {
                const info = root.classify(url);
                if (info && !seen[url]) {
                    seen[url] = true;
                    const name = (label ?? "").replace(/`|\*\*/g, "").trim();
                    links.push({ url: url, name: name.length > 0 && name !== url ? name : info.short, info: info });
                }
                return match;
            });
        }
        root.memo.links[id] = { length: content.length, rules: rules, links: links };
        return links;
    }

    // A line that is nothing but a link: an optional "Label:" in front, then the
    // link as [text](url), <url> or a bare url, possibly bold, then optionally a
    // separator and a remark. { label, url, text, rest } or null.
    function linkOnly(line) {
        let s = line.trim(), label = null, m;
        if ((m = s.match(/^\*\*([^*\[\]]+?)\*\*:?\s*/)) && !/^https?:\/\//i.test(m[1])) {
            label = m[1].replace(/:$/, "");
            s = s.slice(m[0].length);
        } else if ((m = s.match(/^((?:[^\s:*\[\]()<>`]+ ){0,2}[^\s:*\[\]()<>`]+):\s+/))) {
            label = m[1];
            s = s.slice(m[0].length);
        }
        const bold = s.startsWith("**");
        if (bold) s = s.slice(2);
        let url, text = null, length;
        if ((m = s.match(/^\[((?:[^\[\]\n]|\[[^\]\n]*\])+)\]\((https?:\/\/[^)\s]+)\)/i))) {
            text = m[1];
            url = m[2];
            length = m[0].length;
        } else if ((m = s.match(/^<(https?:\/\/[^>\s]+)>/i))) {
            url = m[1];
            length = m[0].length;
        } else if ((m = s.match(/^https?:\/\/[^\s<>]+/i))) {
            url = m[0].replace(/\*+$/, "").replace(/[.,;:!?'"]+$/, "");
            length = url.length;
        } else {
            return null;
        }
        s = s.slice(length);
        if (bold && s.startsWith("**")) s = s.slice(2);
        const rest = s.trim();
        if (rest.length > 0 && !/^[,(—–:-]/.test(rest)) return null;
        return { label: label, url: url, text: text, rest: rest.replace(/^[,:—–-]\s*/, "") };
    }

    // One text block split into prose, card groups ("links") and link lists
    // ("sources"). Only lines that stand alone qualify: top-level list items with
    // no continuation, and single-line paragraphs. While a reply streams its last
    // line may be half a link, so it stays prose until the reply is done.
    function splitLinkLines(content, streaming) {
        const lines = content.split("\n");
        const blank = i => i < 0 || i >= lines.length || lines[i].trim().length === 0;
        const itemOf = i => i >= 0 && i < lines.length ? lines[i].match(/^ ?(?:[-*+]|\d{1,9}[.)])\s+(.*)$/) : null;
        const heading = i => i >= 0 && i < lines.length && /^#{1,6}\s/.test(lines[i]);
        let lastLine = lines.length - 1;
        while (lastLine >= 0 && blank(lastLine)) lastLine--;

        const found = lines.map((line, i) => {
            if (blank(i) || (streaming && i === lastLine)) return null;
            const item = itemOf(i);
            if (item) {
                if (!blank(i + 1) && !itemOf(i + 1)) return null;
            } else if (/^\s/.test(line) || !(blank(i - 1) || heading(i - 1)) || !(blank(i + 1) || heading(i + 1))) {
                return null;
            }
            const link = root.linkOnly(root.linkTicketKeys(item ? item[1] : line));
            const info = link ? root.classify(link.url) : null;
            if (!info) return null;
            link.info = info;
            return { item: item !== null, rich: root.richKinds.includes(info.kind), link: link };
        });

        // A link list only becomes a sources box as a whole list, so a box never
        // leaves half a list behind as prose.
        const source = lines.map(() => false);
        for (let i = 0; i < lines.length;) {
            if (!itemOf(i)) { i++; continue; }
            const run = [];
            let j = i;
            while (j < lines.length && (itemOf(j) || blank(j))) {
                if (itemOf(j)) run.push(j);
                j++;
            }
            const plain = run.filter(k => !found[k]?.rich);
            if (plain.length >= 2 && plain.every(k => found[k] && found[k].link.rest.length === 0)) {
                for (const k of plain) source[k] = true;
            }
            i = j;
        }

        const out = [];
        let text = [];
        let group = null;
        let pendingBlank = [];
        const flushText = () => {
            const joined = text.join("\n");
            if (joined.trim().length > 0) out.push({ type: "text", content: joined });
            text = [];
        };
        lines.forEach((line, i) => {
            if (blank(i)) {
                if (group) pendingBlank.push(line);
                else text.push(line);
                return;
            }
            const type = found[i]?.rich ? "links" : source[i] ? "sources" : "text";
            if (group && group.type === type) {
                pendingBlank = [];
                group.cards.push(found[i].link);
                return;
            }
            group = null;
            text.push(...pendingBlank);
            pendingBlank = [];
            if (type === "text") {
                text.push(line);
                return;
            }
            flushText();
            group = { type: type, content: "", cards: [found[i].link] };
            out.push(group);
        });
        text.push(...pendingBlank);
        flushText();
        return out;
    }

    // splitMarkdownBlocks, with the link lines of each text block pulled out.
    // `streaming` holds back the last line of the last block.
    function proseBlocks(text, streaming) {
        const blocks = StringUtils.splitMarkdownBlocks(text);
        const out = [];
        blocks.forEach((block, i) => {
            if (block.type !== "text" || !root.hasLinks(block.content)) {
                out.push(block);
                return;
            }
            for (const piece of root.splitLinkLines(block.content, streaming && i === blocks.length - 1)) out.push(piece);
        });
        return out;
    }

    // ------------------------------------------------------------------
    // Live state of tickets, PRs, issues and crashes
    // ------------------------------------------------------------------

    readonly property int freshSeconds: 600
    readonly property string metaPath: FileUtils.trimFileProtocol(`${Directories.cache}/claude-links/meta.json`)
    property var meta: ({})

    FileView {
        path: root.metaPath
        onLoaded: {
            try {
                root.meta = Object.assign(JSON.parse(text()), root.meta);
            } catch (e) {}
        }
    }

    function want(ref) {
        if (!ref || root.memo.asked[ref]) return;
        const entry = root.meta[ref];
        if (entry && Date.now() / 1000 - (entry.fetched ?? 0) < root.freshSeconds) return;
        root.memo.asked[ref] = true;
        root.memo.queue.push(ref);
        metaBatch.restart();
    }

    // Cards are built a whole chat at a time, so their lookups go out together.
    Timer {
        id: metaBatch
        interval: 300
        onTriggered: {
            if (metaProcess.running || root.memo.queue.length === 0) return;
            const now = Date.now() / 1000;
            const refs = root.memo.queue.filter(ref => now - (root.meta[ref]?.fetched ?? 0) >= root.freshSeconds);
            root.memo.queue.filter(ref => !refs.includes(ref)).forEach(ref => delete root.memo.asked[ref]);
            root.memo.queue = [];
            if (refs.length === 0) return;
            root.memo.running = refs;
            metaProcess.command = ["python3", Quickshell.shellPath("scripts/claude/link-meta.py"), root.metaPath, ...refs];
            metaProcess.running = true;
        }
    }

    Process {
        id: metaProcess
        onRunningChanged: if (!running && root.memo.queue.length > 0) metaBatch.restart()
        stdout: StdioCollector {
            id: metaOutput
            onStreamFinished: {
                let fresh = {};
                try {
                    fresh = JSON.parse(metaOutput.text);
                } catch (e) {}
                root.meta = Object.assign({}, root.meta, fresh);
                for (const ref of root.memo.running) delete root.memo.asked[ref];
                root.memo.running = [];
            }
        }
    }

    function statusTone(status, category) {
        const s = (status ?? "").toLowerCase();
        if (s.length === 0) return "";
        if (s.includes("review")) return "review";
        if (s.includes("unresolved") || s.includes("blocked")) return "blocked";
        if (s === "merged") return "merged";
        if (category === "done" || /released|done|resolved|cancel|closed|not planned|ignored/.test(s)) return "done";
        if (category === "new" || category === "indeterminate" || /open|to do|in development|in progress/.test(s)) return "open";
        return "other";
    }

    function ago(iso) {
        const at = Date.parse(iso ?? "");
        if (isNaN(at)) return "";
        const minutes = Math.max(0, (Date.now() - at) / 60000);
        if (minutes < 60) return `${Math.round(minutes)}m ago`;
        if (minutes < 1440) return `${Math.round(minutes / 60)}h ago`;
        return `${Math.round(minutes / 1440)}d ago`;
    }
}
