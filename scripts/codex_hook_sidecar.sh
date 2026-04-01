#!/usr/bin/env bash

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

payload=""
if [ ! -t 0 ]; then
    payload="$(cat 2>/dev/null || true)"
fi
[ -n "$payload" ] || exit 0

cache_file="${CODEX_STATUSLINE_HOOK_CACHE_FILE:-/tmp/codex/statusline-hook-cache.json}"
mkdir -p "$(dirname "$cache_file")"

event_name="$(printf '%s' "$payload" | jq -r '.hookEventName // .hook_event_name // empty' 2>/dev/null || true)"
[ -n "$event_name" ] || exit 0

normalize_preview() {
    printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//' | cut -c1-80
}

command_preview="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
command_preview="$(normalize_preview "$command_preview")"
summary=""
source_name=""
prompt_preview=""
exit_code=""

case "$event_name" in
    SessionStart)
        source_name="$(printf '%s' "$payload" | jq -r '.source // empty' 2>/dev/null || true)"
        case "$source_name" in
            resume) summary="resume" ;;
            *) summary="startup" ;;
        esac
        ;;
    PreToolUse)
        summary="bash run"
        ;;
    PostToolUse)
        exit_code="$(
            printf '%s' "$payload" | jq -r '
                (.tool_response | if type == "string" then (fromjson? // .) else . end) as $response
                | if ($response | type) == "object" then
                    ($response.exit_code // $response.exitCode // $response.status // $response.code // empty)
                  else
                    empty
                  end
            ' 2>/dev/null || true
        )"
        case "$exit_code" in
            0) summary="bash ok" ;;
            "") summary="bash done" ;;
            *) summary="bash fail" ;;
        esac
        ;;
    UserPromptSubmit)
        summary="prompt"
        prompt_preview="$(printf '%s' "$payload" | jq -r '.prompt // empty' 2>/dev/null || true)"
        prompt_preview="$(normalize_preview "$prompt_preview")"
        ;;
    Stop)
        summary="stop"
        ;;
    *)
        exit 0
        ;;
esac

updated_at="$(date +%s)"

jq -n \
    --arg event_name "$event_name" \
    --arg summary "$summary" \
    --arg command_preview "$command_preview" \
    --arg source_name "$source_name" \
    --arg prompt_preview "$prompt_preview" \
    --arg exit_code "$exit_code" \
    --argjson updated_at "$updated_at" \
    '{
        hook_event_name: $event_name,
        summary: $summary,
        updated_at: $updated_at
    }
    + (if $command_preview != "" then {command_preview: $command_preview} else {} end)
    + (if $source_name != "" then {source: $source_name} else {} end)
    + (if $prompt_preview != "" then {prompt_preview: $prompt_preview} else {} end)
    + (if $exit_code != "" then {exit_code: $exit_code} else {} end)
    ' > "$cache_file"

exit 0
