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

codex_bin="${CODEX_BIN:-codex}"
refresh_interval="${AICODINGSTATUS_TMUX_INTERVAL:-5}"
project_name="$(basename "$PWD" | tr -cs '[:alnum:]' '-')"
project_name="${project_name#-}"
project_name="${project_name%-}"
if [[ -z "$project_name" ]]; then
    project_name="codex"
fi
session_name="${AICODINGSTATUS_TMUX_SESSION_NAME:-codex-${project_name}}"
project_dir="$PWD"

if ! tmux has-session -t "$session_name" 2>/dev/null; then
    codex_cmd="exec $(printf '%q' "$codex_bin")"
    if [[ $# -gt 0 ]]; then
        codex_cmd+="$(printf ' %q' "$@")"
    fi
    window_cmd="cd $(printf '%q' "$project_dir") && $codex_cmd"
    tmux new-session -d -s "$session_name" "$window_cmd"
fi

for var in CODEX_MODEL_NAME CODEX_STATUSLINE_THEME CODEX_STATUSLINE_LAYOUT \
           CODEX_STATUSLINE_BAR_STYLE CODEX_STATUSLINE_MAX_WIDTH; do
    if [[ -n "${!var:-}" ]]; then
        tmux set-environment -t "$session_name" "$var" "${!var}"
    fi
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

# Detect bars layout: env var > config.toml
_layout="${CODEX_STATUSLINE_LAYOUT:-}"
if [[ -z "$_layout" ]] && [[ -f "$HOME/.codex/config.toml" ]]; then
    _layout=$(sed -n '/^\[statusline\]/,/^\[/{ s/^layout[[:space:]]*=[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p; }' "$HOME/.codex/config.toml" 2>/dev/null | head -1)
fi

if [[ "$_layout" == "bars" ]]; then
    # Multi-line tmux status: line 0 = git, line 1 = overview, line 2 = 5h bar, line 3 = weekly bar
    tmux set-option -t "$session_name" -q status 4
    tmux set-option -t "$session_name" -q status-right ""
    tmux set-option -t "$session_name" -q status-format[0] "  #($status_base --line 1)"
    tmux set-option -t "$session_name" -q status-format[1] "  #($status_base --line 2)"
    tmux set-option -t "$session_name" -q status-format[2] "  #($status_base --line 3)"
    tmux set-option -t "$session_name" -q status-format[3] "  #($status_base --line 4)"
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
