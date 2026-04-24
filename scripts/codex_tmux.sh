#!/usr/bin/env bash
set -euo pipefail

if ! command -v tmux >/dev/null 2>&1; then
    printf 'tmux is required for codex-tmux.\n' >&2
    exit 1
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
status_script="${CODEX_TMUX_STATUS_SCRIPT:-$HOME/.codex/bin/codex-statusline}"
if [[ ! -x "$status_script" ]]; then
    status_script="$script_dir/codex_statusline.sh"
fi
common_script="$script_dir/codex_statusline_common.sh"
if [[ ! -f "$common_script" ]]; then
    printf 'missing shared helper: %s\n' "$common_script" >&2
    exit 1
fi
# shellcheck source=./codex_statusline_common.sh
. "$common_script"

codex_bin="${CODEX_BIN:-codex}"
project_name="$(basename "$PWD" | tr -cs '[:alnum:]' '-')"
project_name="${project_name#-}"
project_name="${project_name%-}"
if [[ -z "$project_name" ]]; then
    project_name="codex"
fi
session_name="${AICODINGSTATUS_TMUX_SESSION_NAME:-codex-${project_name}}"
project_dir="$PWD"
config_file="$HOME/.codex/config.toml"
session_base="${CODEX_STATUSLINE_SESSION_DIR:-$HOME/.codex/sessions}"

legacy_refresh_interval=$(statusline_resolve_positive_int_setting "${AICODINGSTATUS_TMUX_INTERVAL:-}" "5")
refresh_interval=$(statusline_resolve_positive_int_setting "${CODEX_STATUSLINE_REFRESH_INTERVAL:-$(statusline_toml_get "$config_file" refresh_interval "")}" "$legacy_refresh_interval")

find_session_files() {
    find "$session_base" -name "*.jsonl" -type f 2>/dev/null | sort
}

find_new_session_file() {
    local previous_snapshot="$1"
    local candidate

    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        if ! printf '%s\n' "$previous_snapshot" | grep -Fqx -- "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(find "$session_base" -name "*.jsonl" -type f 2>/dev/null | sort -r)

    return 1
}

wait_for_new_session_file() {
    local previous_snapshot="$1"
    local attempt=0
    local max_attempts=30
    local candidate=""

    while [ "$attempt" -lt "$max_attempts" ]; do
        candidate=$(find_new_session_file "$previous_snapshot" 2>/dev/null || true)
        if [ -n "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
        sleep 0.2
        attempt=$(( attempt + 1 ))
    done

    return 1
}

if ! tmux has-session -t "$session_name" 2>/dev/null; then
    existing_session_files=$(find_session_files)
    codex_cmd="exec $(printf '%q' "$codex_bin")"
    if [[ $# -gt 0 ]]; then
        codex_cmd+="$(printf ' %q' "$@")"
    fi
    window_cmd="cd $(printf '%q' "$project_dir") && $codex_cmd"
    tmux new-session -d -s "$session_name" "$window_cmd"

    new_session_file=$(wait_for_new_session_file "$existing_session_files" 2>/dev/null || true)
    if [[ -n "$new_session_file" ]]; then
        tmux set-environment -t "$session_name" CODEX_STATUSLINE_SESSION_FILE "$new_session_file"
    fi
fi

for var in CODEX_MODEL_NAME CODEX_STATUSLINE_THEME CODEX_STATUSLINE_LAYOUT \
           CODEX_STATUSLINE_BAR_STYLE CODEX_STATUSLINE_MAX_WIDTH \
           CODEX_STATUSLINE_REFRESH_INTERVAL CODEX_STATUSLINE_SESSION_DIR \
           CODEX_STATUSLINE_SESSION_FILE \
           CODEX_STATUSLINE_SHOW_BUDDY_SEGMENT CODEX_STATUSLINE_BUDDY_CACHE_FILE \
           CODEX_STATUSLINE_BUDDY_TTL; do
    if [[ -n "${!var:-}" ]]; then
        tmux set-environment -t "$session_name" "$var" "${!var}"
    fi
done

for var in CODEX_STATUSLINE_SHOW_GIT_LINE CODEX_STATUSLINE_SHOW_OVERVIEW_LINE; do
    tmux set-environment -t "$session_name" "$var" "${!var-}"
done

status_base="$(printf '%q %q' "$status_script" "$project_dir")"
tmux set-option -t "$session_name" -q status on
tmux set-option -t "$session_name" -q status-position bottom
tmux set-option -t "$session_name" -q status-justify left
tmux set-option -t "$session_name" -q status-left-length 0
tmux set-option -t "$session_name" -q status-right-length 160
tmux set-option -t "$session_name" -q status-style "bg=#1f2430,fg=#c0c5ce"
tmux set-option -t "$session_name" -q status-interval "$refresh_interval"
tmux set-option -t "$session_name" -q status-left ""

# Detect bars layout and visible lines: env var > config.toml
_layout="${CODEX_STATUSLINE_LAYOUT:-$(statusline_toml_get "$config_file" layout "")}"
_show_git_line=$(statusline_resolve_bool_setting "${CODEX_STATUSLINE_SHOW_GIT_LINE:-$(statusline_toml_get "$config_file" show_git_line "")}" "1")
_show_overview_line=$(statusline_resolve_bool_setting "${CODEX_STATUSLINE_SHOW_OVERVIEW_LINE:-$(statusline_toml_get "$config_file" show_overview_line "")}" "1")

if [[ "$_layout" == "bars" ]]; then
    # Multi-line tmux status: line 0 = git, line 1 = overview, line 2 = 5h bar, line 3 = weekly bar
    visible_lines=()
    [[ "$_show_git_line" == "1" ]] && visible_lines+=(1)
    [[ "$_show_overview_line" == "1" ]] && visible_lines+=(2)
    visible_lines+=(3 4)

    tmux set-option -t "$session_name" -q status "${#visible_lines[@]}"
    tmux set-option -t "$session_name" -q status-right ""
    for idx in "${!visible_lines[@]}"; do
        tmux set-option -t "$session_name" -q "status-format[$idx]" "  #($status_base --line ${visible_lines[$idx]})"
    done
    for ((idx=${#visible_lines[@]}; idx<4; idx++)); do
        tmux set-option -t "$session_name" -q "status-format[$idx]" ""
    done
else
    tmux set-option -t "$session_name" -q status 1
    tmux set-option -t "$session_name" -q status-left "  #($status_base)"
    tmux set-option -t "$session_name" -q status-left-length 160
    tmux set-option -t "$session_name" -q status-right ""
fi

if [[ -n "${TMUX:-}" ]]; then
    exec tmux switch-client -t "$session_name"
else
    exec tmux attach-session -t "$session_name"
fi
