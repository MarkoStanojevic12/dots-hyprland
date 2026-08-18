pragma Singleton
import Quickshell

Singleton {
    id: root
    /**
     * @param { string } summary 
     * @returns { string }
     */
    function findSuitableMaterialSymbol(summary = "") {
        const defaultType = 'chat';
        if (summary.length === 0) return defaultType;

        const keywordsToTypes = {
            'reboot': 'restart_alt',
            'record': 'screen_record',
            'battery': 'power',
            'power': 'power',
            'screenshot': 'screenshot_monitor',
            'welcome': 'waving_hand',
            'time': 'scheduleb',
            'installed': 'download',
            'configuration reloaded': 'reset_wrench',
            'unable': 'question_mark',
            "couldn't": 'question_mark',
            'config': 'reset_wrench',
            'update': 'update',
            'ai response': 'neurology',
            'control': 'settings',
            'upsca': 'compare',
            'music': 'queue_music',
            'install': 'deployed_code_update',
            'input': 'keyboard_alt',
            'preedit': 'keyboard_alt',
            'startswith:file': 'folder_copy', // Declarative startsWith check
        };

        const lowerSummary = summary.toLowerCase();

        for (const [keyword, type] of Object.entries(keywordsToTypes)) {
            if (keyword.startsWith('startswith:')) {
                const startsWithKeyword = keyword.replace('startswith:', '');
                if (lowerSummary.startsWith(startsWithKeyword)) {
                    return type;
                }
            } else if (lowerSummary.includes(keyword)) {
                return type;
            }
        }

        return defaultType;
    }

    /**
     * @param { number | string | Date } timestamp 
     * @returns { string }
     */
    function getFriendlyNotifTimeString(timestamp) {
        if (!timestamp) return '';
        const messageTime = new Date(timestamp);
        const now = new Date();
        const diffMs = now.getTime() - messageTime.getTime();

        // Less than 1 minute
        if (diffMs < 60000)
            return 'Now';

        // Same day - show relative time
        if (messageTime.toDateString() === now.toDateString()) {
            const diffMinutes = Math.floor(diffMs / 60000);
            const diffHours = Math.floor(diffMs / 3600000);

            if (diffHours > 0) {
                return `${diffHours}h`;
            } else {
                return `${diffMinutes}m`;
            }
        }

        // Yesterday
        if (messageTime.toDateString() === new Date(now.getTime() - 86400000).toDateString())
            return 'Yesterday';

        // Older dates
        return Qt.formatDateTime(messageTime, "MMMM dd");
    }

    /**
     * Material symbol for a notification action button, or "" when the action's
     * own label should be shown instead. Longest/most specific keywords first,
     * so "Open folder" picks the folder icon rather than the generic open one.
     * @param { string } actionText
     * @returns { string }
     */
    function findActionMaterialSymbol(actionText = "") {
        if (actionText.length === 0) return "";

        const keywordsToTypes = {
            'folder': 'folder_open',
            'directory': 'folder_open',
            'reply': 'reply',
            'copy': 'content_copy',
            'download': 'download',
            'snooze': 'snooze',
            'dismiss': 'close',
            'cancel': 'close',
            'retry': 'refresh',
            'again': 'refresh',
            'undo': 'undo',
            'settings': 'settings',
            'open': 'open_in_new',
            'show': 'open_in_new',
            'view': 'open_in_new',
        };

        const lowerText = actionText.toLowerCase();

        for (const [keyword, symbol] of Object.entries(keywordsToTypes)) {
            if (lowerText.includes(keyword)) return symbol;
        }

        return "";
    }

    /**
     * Puts a notification body on the clipboard.
     * When the body is just a path to an existing file (e.g. the recording a
     * finished screen capture wrote), the file itself is copied as a clipboard
     * file reference instead of its path as text, so it can be pasted into
     * file managers, chat apps and the like.
     * @param { string } body
     */
    function copyBody(body) {
        const trimmed = (body ?? "").trim();
        const path = trimmed.startsWith("file://") ? decodeURIComponent(trimmed.slice("file://".length)) : trimmed;

        // Anything that can't be a single absolute path is plain text
        if (!path.startsWith("/") || path.includes("\n")) {
            Quickshell.clipboardText = body;
            return;
        }

        // Whether the file exists can only be decided at click time, so the
        // fallback to plain text lives in the script. Positional args keep the
        // values out of the script text, so nothing needs escaping.
        const uri = "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F");
        Quickshell.execDetached(["bash", "-c",
            'if [ -f "$1" ]; then printf "%s\\r\\n" "$2" | wl-copy -t text/uri-list; else printf "%s" "$3" | wl-copy; fi',
            "notification-copy", path, uri, body ?? ""]);
    }

    function processNotificationBody(body, appName) {
        let processedBody = body
        
        // Clean Chromium-based browsers notifications - remove first line
        if (appName) {
            const lowerApp = appName.toLowerCase()
            const chromiumBrowsers = [
                "brave", "chrome", "chromium", "vivaldi", "opera", "microsoft edge"
            ]

            if (chromiumBrowsers.some(name => lowerApp.includes(name))) {
                const lines = body.split('\n\n')

                if (lines.length > 1 && lines[0].startsWith('<a')) {
                    processedBody = lines.slice(1).join('\n\n')
                }
            }
        }

        processedBody = processedBody.replace(/<img/gi, '\n\n<img');
        
        return processedBody
    }
}
