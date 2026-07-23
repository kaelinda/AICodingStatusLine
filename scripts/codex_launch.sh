#!/usr/bin/env bash
# codex-launch — smart Codex CLI launcher.
#
# Decides between `codex-tmux` (enhanced HUD) and plain `codex` (native
# tui.status_line) based on:
#   - presence of tmux
#   - presence of ~/.codex/bin/codex-tmux (install.sh --target codex)
#   - whether current directory is a git repo (so branch info is worth showing)
#
# Flags:
#   --force-native   always use plain `codex`
#   --force-tmux     always use codex-tmux (fail if missing)
#   --dry-run        print decision without exec'ing anything
#   --session NAME   override tmux session name
#   -h | --help
#
# All remaining args are forwarded to the chosen backend.

set -euo pipefail

force_mode=""
dry_run=0
session_name=""

while [ $# -gt 0 ]; do
    case "$1" in
        --force-native) force_mode="native"; shift ;;
        --force-tmux)   force_mode="tmux";   shift ;;
        --dry-run)      dry_run=1;           shift ;;
        --session)
            if [ $# -lt 2 ] || [ -z "${2:-}" ] || [ "${2#-}" != "$2" ]; then
                printf '[codex-launch] --session requires a non-empty NAME argument.\n' >&2
                exit 2
            fi
            session_name="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --) shift; break ;;
        *)  break ;;
    esac
done

codex_bin="${CODEX_BIN:-codex}"
tmux_wrapper="${CODEX_TMUX_BIN:-$HOME/.codex/bin/codex-tmux}"

have_tmux=0
command -v tmux >/dev/null 2>&1 && have_tmux=1

have_wrapper=0
[ -x "$tmux_wrapper" ] && have_wrapper=1

# Detect git repo + branch for logging (also used to hint statusline preset).
repo_root=""
branch_name=""
if command -v git >/dev/null 2>&1; then
    if repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        branch_name=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "")
    fi
fi

repo_display="-"
if [ -n "$repo_root" ]; then
    repo_display="$(basename "$repo_root")"
fi
branch_display="${branch_name:--}"

decide_mode() {
    if [ -n "$force_mode" ]; then
        printf '%s\n' "$force_mode"
        return
    fi
    if [ "$have_tmux" -eq 1 ] && [ "$have_wrapper" -eq 1 ]; then
        printf 'tmux\n'
        return
    fi
    printf 'native\n'
}

mode=$(decide_mode)

# Explain the choice.
reason=""
case "$mode" in
    tmux)
        reason="tmux found, git repo detected"
        [ -z "$repo_root" ] && reason="tmux found, non-git dir (branch segment will be empty)"
        if [ "$force_mode" = "tmux" ] && [ "$have_wrapper" -eq 0 ]; then
            printf '[codex-launch] --force-tmux requested but %s is missing.\n' "$tmux_wrapper" >&2
            printf '[codex-launch] run: install.sh --target codex\n' >&2
            exit 2
        fi
        if [ "$force_mode" = "tmux" ] && [ "$have_tmux" -eq 0 ]; then
            printf '[codex-launch] --force-tmux requested but tmux is not installed.\n' >&2
            exit 2
        fi
        ;;
    native)
        if [ "$have_tmux" -eq 0 ]; then
            reason="tmux missing, falling back to native"
        elif [ "$have_wrapper" -eq 0 ]; then
            reason="codex-tmux not installed, falling back to native"
        else
            reason="forced native"
        fi
        ;;
esac

# Statusline hints — surface intended layout to whoever reads the log.
sl_git_display="repo"
sl_show_git_line=1
if [ -z "$repo_root" ]; then
    sl_git_display="branch"
    sl_show_git_line=0
fi

printf '[codex-launch] repo=%s branch=%s\n' "$repo_display" "$branch_display"
printf '[codex-launch] mode=%s (%s)\n' "$mode" "$reason"
printf '[codex-launch] statusline: git_display=%s, show_git_line=%s\n' "$sl_git_display" "$sl_show_git_line"

# Compose the target command.
target_cmd=()
if [ "$mode" = "tmux" ]; then
    target_cmd+=("$tmux_wrapper")
    [ -n "$session_name" ] && export AICODINGSTATUS_TMUX_SESSION_NAME="$session_name"
    # Nudge the statusline preset toward showing the branch line.
    export CODEX_STATUSLINE_GIT_DISPLAY="${CODEX_STATUSLINE_GIT_DISPLAY:-$sl_git_display}"
    export CODEX_STATUSLINE_SHOW_GIT_LINE="${CODEX_STATUSLINE_SHOW_GIT_LINE:-$sl_show_git_line}"
else
    target_cmd+=("$codex_bin")
fi

if [ "$#" -gt 0 ]; then
    target_cmd+=("$@")
fi

if [ "$dry_run" -eq 1 ]; then
    printf '[codex-launch] would exec:'
    for arg in "${target_cmd[@]}"; do
        printf ' %q' "$arg"
    done
    printf '\n'
    exit 0
fi

exec "${target_cmd[@]}"
