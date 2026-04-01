#!/usr/bin/env bash

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

stdin_payload=""
if [ ! -t 0 ]; then
    stdin_payload="$(cat 2>/dev/null || true)"
fi
payload="${stdin_payload:-${1:-}}"
[ -n "$payload" ] || exit 0

cache_file="${CODEX_NOTIFY_BRIDGE_CACHE_FILE:-/tmp/codex/statusline-notify-cache.json}"
mkdir -p "$(dirname "$cache_file")"

normalize_preview() {
    printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//' | cut -c1-160
}

extract_first_string() {
    local program="$1"
    printf '%s' "$payload" | jq -r "$program" 2>/dev/null || true
}

if printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then
    title="$(extract_first_string '[.title, .source, .app, "Codex"] | map(select(type == "string" and . != "")) | .[0] // "Codex"')"
    message="$(extract_first_string '[.message, .body, .summary, .text, .content, .statusMessage, .status_message] | map(select(type == "string" and . != "")) | .[0] // "Codex sent a notification"')"
    level="$(extract_first_string '[.level, .status, .severity] | map(select(type == "string" and . != "")) | .[0] // "info"')"
    source_name="$(extract_first_string '[.type, .event, .event_type] | map(select(type == "string" and . != "")) | .[0] // empty')"
else
    title="Codex"
    message="$payload"
    level="info"
    source_name=""
fi

title="$(normalize_preview "${title:-Codex}")"
message="$(normalize_preview "${message:-Codex sent a notification}")"
level="$(normalize_preview "${level:-info}")"
source_name="$(normalize_preview "${source_name:-}")"
summary="$(normalize_preview "$(extract_first_string '[.summary, .message, .body, .text, .content, .statusMessage, .status_message] | map(select(type == "string" and . != "")) | .[0] // empty')")"
if [ -z "$summary" ]; then
    summary="$message"
fi
updated_at="$(date +%s)"

jq -n \
    --arg title "$title" \
    --arg message "$message" \
    --arg level "$level" \
    --arg summary "$summary" \
    --arg source_name "$source_name" \
    --argjson updated_at "$updated_at" \
    '{
        title: $title,
        message: $message,
        level: $level,
        summary: $summary,
        updated_at: $updated_at
    }
    + (if $source_name != "" then {source: $source_name} else {} end)
    ' > "$cache_file"

case "${CODEX_NOTIFY_BRIDGE_DISABLE_DESKTOP:-0}" in
    1|true|TRUE|yes|YES) exit 0 ;;
esac

send_macos_notification() {
    command -v osascript >/dev/null 2>&1 || return 1

    osascript - "$title" "$level" "$message" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
    set notificationTitle to item 1 of argv
    set notificationSubtitle to item 2 of argv
    set notificationMessage to item 3 of argv

    if notificationSubtitle is "" then
        display notification notificationMessage with title notificationTitle
    else
        display notification notificationMessage with title notificationTitle subtitle notificationSubtitle
    end if
end run
APPLESCRIPT
}

send_linux_notification() {
    command -v notify-send >/dev/null 2>&1 || return 1
    notify-send "$title" "$message" >/dev/null 2>&1
}

case "$(uname -s)" in
    Darwin) send_macos_notification || true ;;
    Linux) send_linux_notification || true ;;
esac

exit 0
