#!/usr/bin/env bash
# Jira Cloud REST helper for the bar ticket widget (services/Jira.qml).
#
# Config: ~/.config/illogical-impulse/jira.json
#   { "site": "https://<org>.atlassian.net", "email": "<login>",
#     "project": "<KEY>", "repos": ["/path/to/repo", ...] }
# Token (https://id.atlassian.com/manage-profile/security/api-tokens):
#   secret-tool store --label="Jira API token" service jira-api account <email>
#
# Every command prints one JSON document; failures print {"error": "..."} and
# exit non-zero.
set -uo pipefail

config="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/jira.json"

fail() { jq -cn --arg e "$1" '{error: $e}'; exit "${2:-1}"; }

[ -f "$config" ] || fail "no config at $config" 3
site=$(jq -r '.site // empty' "$config"); site=${site%/}
email=$(jq -r '.email // empty' "$config")
project=$(jq -r '.project // empty' "$config")
key_pattern="${project:-[A-Z][A-Z0-9]+}-[0-9]+"

# request METHOD PATH [JSON]  -> body on stdout, or fail() with Jira's message
request() {
    [ -n "$site" ] && [ -n "$email" ] || fail "config needs site and email" 3
    local token
    token=$(secret-tool lookup service jira-api account "$email" 2>/dev/null)
    [ -n "$token" ] || fail "no API token in the keyring for $email" 4

    local args=(-sS -X "$1" --max-time 20 -H "Accept: application/json" -w '\n%{http_code}')
    [ $# -ge 3 ] && args+=(-H "Content-Type: application/json" --data-binary "$3")

    local out code body
    # Credentials go in through stdin so the token never shows up in ps.
    out=$(curl "${args[@]}" -K - "$site/rest/api/3/$2" <<<"user = \"$email:$token\"" 2>&1) \
        || fail "request failed: ${out%$'\n'*}"
    code=${out##*$'\n'}
    body=${out%$'\n'*}
    if [ "$code" -ge 400 ]; then
        local message
        message=$(jq -r '[.errorMessages[]?, (.errors // {} | to_entries[] | "\(.key): \(.value)")] | join("; ")' <<<"$body" 2>/dev/null)
        fail "HTTP $code${message:+: $message}"
    fi
    printf '%s' "$body"
}

# fetch VAR METHOD PATH [JSON] -- request() into VAR in this shell, so its
# error document reaches stdout instead of being piped into the next jq.
fetch() {
    local -n _into=$1; shift
    _into=$(request "$@") || { printf '%s\n' "$_into"; exit 1; }
}

need_key() { [[ "${1:-}" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]] || fail "not an issue key: ${1:-}" 2; }

cmd=${1:-}; shift || true
case "$cmd" in
issue)
    need_key "${1:-}"
    fetch body GET "issue/$1?fields=summary,status,assignee,reporter,priority,issuetype,description,comment,subtasks,parent,updated&expand=renderedFields"
    jq -c --arg site "$site" '
            .renderedFields as $r | .fields as $f | {
                key, url: "\($site)/browse/\(.key)",
                summary: $f.summary,
                status: $f.status.name,
                statusCategory: $f.status.statusCategory.key,
                type: $f.issuetype.name,
                priority: $f.priority.name,
                assignee: ($f.assignee | if . then {id: .accountId, name: .displayName} else null end),
                reporter: $f.reporter.displayName,
                updated: $f.updated,
                parent: ($f.parent | if . then {key, summary: .fields.summary} else null end),
                subtasks: [$f.subtasks[]? | {key, summary: .fields.summary, status: .fields.status.name}],
                description: ($r.description // ""),
                commentCount: ($f.comment.total // 0),
                comments: [($f.comment.comments // []) as $c | range(0; $c | length) as $i | {
                    author: $c[$i].author.displayName,
                    created: $c[$i].created,
                    body: ($r.comment.comments[$i].body // "")
                }] | .[-5:]
            }' <<<"$body"
    ;;
transitions)
    need_key "${1:-}"
    fetch body GET "issue/$1/transitions"
    jq -c '[.transitions[] | {id, name, to: .to.name}]' <<<"$body"
    ;;
transition)
    need_key "${1:-}"
    [ -n "${2:-}" ] || fail "transition needs an id" 2
    fetch body POST "issue/$1/transitions" "$(jq -cn --arg id "$2" '{transition: {id: $id}}')"
    echo '{"ok":true}'
    ;;
comment)
    need_key "${1:-}"
    [[ "${2:-}" =~ [^[:space:]] ]] || fail "empty comment" 2
    # Blank lines split paragraphs, single newlines become hard breaks.
    payload=$(jq -cn --arg text "$2" '{body: {type: "doc", version: 1, content: [
        $text | sub("^\\s+"; "") | sub("\\s+$"; "") | split("\n\n")[] | select(test("\\S")) | {type: "paragraph", content: [
            split("\n") | to_entries[] |
                (if .key > 0 then {type: "hardBreak"} else empty end),
                (select(.value != "") | {type: "text", text: .value})
        ]}
    ]}}')
    fetch body POST "issue/$1/comment" "$payload"
    echo '{"ok":true}'
    ;;
assign)
    need_key "${1:-}"
    account=${2:-}
    case "$account" in
        me) fetch body GET myself
            payload=$(jq -c '{accountId}' <<<"$body") ;;
        none) payload='{"accountId":null}' ;;
        "") fail "assign needs an account id, me or none" 2 ;;
        *) payload=$(jq -cn --arg id "$account" '{accountId: $id}') ;;
    esac
    fetch body PUT "issue/$1/assignee" "$payload"
    echo '{"ok":true}'
    ;;
users)
    need_key "${1:-}"
    query=$(jq -rn --arg q "${2:-}" '$q | @uri')
    fetch body GET "user/assignable/search?issueKey=$1&query=$query&maxResults=8"
    jq -c '[.[] | {id: .accountId, name: .displayName}]' <<<"$body"
    ;;
branch)
    # The repo whose HEAD moved last wins, so a fresh checkout takes over.
    best_key=""; best_repo=""; best_time=0
    while IFS= read -r repo; do
        repo=${repo/#\~/$HOME}
        head=$(git -C "$repo" rev-parse --path-format=absolute --git-path HEAD 2>/dev/null) || continue
        branch=$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null) || continue
        key=$(grep -oE "$key_pattern" <<<"$branch" | head -n1)
        [ -n "$key" ] || continue
        time=$(stat -c %Y "$head")
        if [ "$time" -gt "$best_time" ]; then
            best_key=$key; best_repo=$repo; best_time=$time
        fi
    done < <(jq -r '.repos[]?' "$config")
    jq -cn --arg key "$best_key" --arg repo "$best_repo" --argjson time "$best_time" \
        'if $key == "" then {key: null} else {key: $key, repo: $repo, time: $time} end'
    ;;
*)
    fail "usage: jira.sh issue|transitions|transition|comment|assign|users|branch ..." 2
    ;;
esac
