#!/bin/bash

set -f

# Codex CLI status line — reads model/effort from config.toml,
# token usage and rate limits from session JSONL files.

script_dir="$(cd "$(dirname "$0")" && pwd)"
common_script="$script_dir/codex_statusline_common.sh"
if [ ! -f "$common_script" ]; then
    printf 'missing shared helper: %s\n' "$common_script" >&2
    exit 1
fi
# shellcheck source=./codex_statusline_common.sh
. "$common_script"

# Parse arguments: codex_statusline.sh [project_dir] [--line N]
target_dir="$PWD"
line_select=0
while [ $# -gt 0 ]; do
    case "$1" in
        --line) line_select="$2"; shift 2 ;;
        *) target_dir="$1"; shift ;;
    esac
done
if [ -d "$target_dir" ]; then
    target_dir="$(cd "$target_dir" && pwd)"
else
    target_dir="$PWD"
fi

config_file="$HOME/.codex/config.toml"
session_base="${CODEX_STATUSLINE_SESSION_DIR:-$HOME/.codex/sessions}"
session_file_override="${CODEX_STATUSLINE_SESSION_FILE:-}"
theme_name="${CODEX_STATUSLINE_THEME:-$(statusline_toml_get "$config_file" theme default)}"
layout_name="${CODEX_STATUSLINE_LAYOUT:-$(statusline_toml_get "$config_file" layout bars)}"
bar_style_name="${CODEX_STATUSLINE_BAR_STYLE:-$(statusline_toml_get "$config_file" bar_style ascii)}"
git_display_mode="${CODEX_STATUSLINE_GIT_DISPLAY:-$(statusline_toml_get "$config_file" git_display repo)}"

# Output format: tmux (#[fg=...]) vs ansi (\033[...m)
# Auto-detect: use tmux format when TMUX is set, unless overridden.
output_format="${CODEX_STATUSLINE_FORMAT:-}"
if [ -z "$output_format" ]; then
    if [ -n "${TMUX:-}" ]; then
        output_format="tmux"
    else
        output_format="ansi"
    fi
fi

case "$layout_name" in
    bars|compact) ;;
    *) layout_name="bars" ;;
esac
case "$git_display_mode" in
    repo|branch) ;;
    *) git_display_mode="repo" ;;
esac
segments_raw="${CODEX_STATUSLINE_SEGMENTS:-$(statusline_toml_get "$config_file" segments "")}"
segments_filter_active=0
segments_csv=""
default_segment_order_csv="model,eff,ctx,git,5h,7d,hook,notify,buddy"
ordered_segments=()
if [ -n "$segments_raw" ]; then
    segments_filter_active=1
    segments_csv=",$(printf '%s' "$segments_raw" | tr -d '[:space:]'),"
fi
segment_enabled() {
    [ "$segments_filter_active" -eq 0 ] && return 0
    case "$segments_csv" in *,"$1",*) return 0 ;; esac
    return 1
}
append_segment_order() {
    local segment_name="$1"
    local existing_segment

    for existing_segment in "${ordered_segments[@]}"; do
        [ "$existing_segment" = "$segment_name" ] && return 0
    done

    ordered_segments+=("$segment_name")
}

initialize_segment_order() {
    local raw_item segment_name

    ordered_segments=()

    for raw_item in $(printf '%s' "${segments_raw:-$default_segment_order_csv}" | tr ',' ' '); do
        segment_name=$(printf '%s' "$raw_item" | tr -d '[:space:]')
        case "$segment_name" in
            model|eff|ctx|git|5h|7d|hook|notify|buddy)
                append_segment_order "$segment_name"
                ;;
        esac
    done

    for raw_item in $(printf '%s' "$default_segment_order_csv" | tr ',' ' '); do
        append_segment_order "$raw_item"
    done
}
case "$bar_style_name" in
    dots)
        bar_filled_char='●'
        bar_empty_char='○'
        ;;
    squares)
        bar_filled_char='■'
        bar_empty_char='□'
        ;;
    blocks)
        bar_filled_char='█'
        bar_empty_char='░'
        ;;
    braille)
        bar_filled_char='⣿'
        bar_empty_char='⣀'
        ;;
    shades)
        bar_filled_char='▓'
        bar_empty_char='░'
        ;;
    diamonds)
        bar_filled_char='◆'
        bar_empty_char='◇'
        ;;
    custom:*)
        bar_filled_char="$(printf '%s' "$bar_style_name" | cut -d: -f2)"
        bar_empty_char="$(printf '%s' "$bar_style_name" | cut -d: -f3)"
        [ -z "$bar_filled_char" ] && bar_filled_char='='
        [ -z "$bar_empty_char" ] && bar_empty_char='-'
        ;;
    *)
        bar_style_name="ascii"
        bar_filled_char='='
        bar_empty_char='-'
        ;;
esac

# Color palette — theme hex values (R;G;B triplets)
# Mapped to either ANSI or tmux format below.
case "$theme_name" in
    forest)    _accent="120;196;120" _teal="94;170;150" _branch="214;224;205" _muted="138;150;130" _red="224;108;117" _orange="214;170;84" _yellow="198;183;101" _green="120;196;120" _white="234;238;228" ;;
    dracula)   _accent="189;147;249" _teal="139;233;253" _branch="248;248;242" _muted="132;145;182" _red="255;85;85" _orange="255;184;108" _yellow="241;250;140" _green="80;250;123" _white="248;248;242" ;;
    monokai)   _accent="102;217;239" _teal="166;226;46" _branch="230;219;116" _muted="153;147;101" _red="249;38;114" _orange="253;151;31" _yellow="230;219;116" _green="166;226;46" _white="248;248;242" ;;
    solarized) _accent="38;139;210" _teal="42;161;152" _branch="147;161;161" _muted="133;149;150" _red="220;50;47" _orange="203;75;22" _yellow="181;137;0" _green="133;153;0" _white="238;232;213" ;;
    ocean)     _accent="0;188;212" _teal="0;151;167" _branch="178;235;242" _muted="124;150;162" _red="239;83;80" _orange="255;152;0" _yellow="255;213;79" _green="102;187;106" _white="224;247;250" ;;
    sunset)    _accent="255;138;101" _teal="255;183;77" _branch="255;204;128" _muted="167;140;127" _red="239;83;80" _orange="255;112;66" _yellow="255;213;79" _green="174;213;129" _white="255;243;224" ;;
    amber)     _accent="255;193;7" _teal="220;184;106" _branch="240;230;200" _muted="158;148;119" _red="232;98;92" _orange="232;152;62" _yellow="212;170;50" _green="140;179;105" _white="245;240;224" ;;
    rose)      _accent="244;143;177" _teal="206;147;216" _branch="248;215;224" _muted="173;139;159" _red="239;83;80" _orange="255;138;101" _yellow="255;213;79" _green="165;214;167" _white="253;232;239" ;;
    *)         _accent="96;165;250" _teal="45;212;191" _branch="226;232;240" _muted="148;163;184" _red="248;113;113" _orange="251;146;60" _yellow="251;191;36" _green="52;211;153" _white="229;231;235" ;;
esac

_track="71;85;105"

# Convert R;G;B triplets to output format
_rgb_to_hex() {
    local IFS=';'; set -- $1
    printf '#%02x%02x%02x' "$1" "$2" "$3"
}

if [ "$output_format" = "tmux" ]; then
    accent="#[fg=$(_rgb_to_hex "$_accent")]"
    teal="#[fg=$(_rgb_to_hex "$_teal")]"
    branch="#[fg=$(_rgb_to_hex "$_branch")]"
    muted="#[fg=$(_rgb_to_hex "$_muted")]"
    red="#[fg=$(_rgb_to_hex "$_red")]"
    orange="#[fg=$(_rgb_to_hex "$_orange")]"
    yellow="#[fg=$(_rgb_to_hex "$_yellow")]"
    green="#[fg=$(_rgb_to_hex "$_green")]"
    white="#[fg=$(_rgb_to_hex "$_white")]"
    track="#[fg=$(_rgb_to_hex "$_track")]"
    bold='#[bold]'
    dim='#[dim]'
    reset='#[default]'
else
    accent="\033[38;2;${_accent}m"
    teal="\033[38;2;${_teal}m"
    branch="\033[38;2;${_branch}m"
    muted="\033[38;2;${_muted}m"
    red="\033[38;2;${_red}m"
    orange="\033[38;2;${_orange}m"
    yellow="\033[38;2;${_yellow}m"
    green="\033[38;2;${_green}m"
    white="\033[38;2;${_white}m"
    track="\033[38;2;${_track}m"
    bold='\033[1m'
    dim='\033[2m'
    reset='\033[0m'
fi

# Semantic aliases keep downstream segment builders readable.
primary="$white"
secondary="$muted"
strong="$branch"

sep_plain=' | '
sep_text=" ${dim}|${reset} "
default_two_week_time_format='%-m/%-d %-H:%M reset'
seven_day_time_format='%m/%d %H:%M'
short_seven_day_date_format='%-m/%-d'
weekly_label='weekly'

SEG_TEXT=""
SEG_PLAIN=""
COMPOSED_TEXT=""
COMPOSED_PLAIN=""
COMPOSED_LEN=0
BRANCH_SEGMENT_LEN=0
OUTPUT_TEXT=""
LINE_TEXT=""
LINE_PLAIN=""

# ── Data collection ──────────────────────────────────────────────

resolve_model() {
    local m="${CODEX_MODEL_NAME:-${CODEX_MODEL:-${OPENAI_MODEL:-${MODEL:-}}}}"
    if [ -z "$m" ] && [ -f "$config_file" ]; then
        m=$(grep '^model\s*=' "$config_file" 2>/dev/null | head -1 | sed 's/^model[[:space:]]*=[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    fi
    printf "%s" "${m:-codex}"
}

resolve_effort() {
    local e="${CODEX_EFFORT_LEVEL:-}"
    if [ -z "$e" ] && [ -f "$config_file" ]; then
        e=$(grep '^model_reasoning_effort\s*=' "$config_file" 2>/dev/null | head -1 | sed 's/^model_reasoning_effort[[:space:]]*=[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    fi
    printf "%s" "${e:-medium}"
}

is_valid_two_week_time_format() {
    local value="$1"
    [[ "$value" =~ ^(%[yYmdHMbB]|[[:space:]/:-])+$ ]]
}

resolve_two_week_time_format() {
    local requested="$1"

    if [ -n "$requested" ] && is_valid_two_week_time_format "$requested"; then
        printf "%s" "$requested"
        return
    fi

    printf "%s" "$default_two_week_time_format"
}

find_latest_session() {
    if [ -n "$session_file_override" ] && [ -f "$session_file_override" ]; then
        printf '%s\n' "$session_file_override"
        return 0
    fi

    find "$session_base" -name "*.jsonl" -type f 2>/dev/null | sort -r | head -1
}

find_latest_token_count_line_in_file() {
    local session_file="$1"
    local preferred_line latest_line candidate
    local preferred_limit_id="${CODEX_STATUSLINE_PRIMARY_LIMIT_ID:-codex}"

    [ -z "$session_file" ] && return 1

    if command -v jq >/dev/null 2>&1; then
        if command -v tac >/dev/null 2>&1; then
            while IFS= read -r candidate; do
                [[ "$candidate" == *'"token_count"'* ]] || continue
                if [ -z "$latest_line" ]; then
                    latest_line="$candidate"
                fi
                if printf '%s' "$candidate" | jq -e --arg preferred_limit_id "$preferred_limit_id" \
                    '.payload.rate_limits.limit_id == $preferred_limit_id' >/dev/null 2>&1; then
                    preferred_line="$candidate"
                    break
                fi
            done < <(tac "$session_file")
        else
            while IFS= read -r candidate; do
                [[ "$candidate" == *'"token_count"'* ]] || continue
                if [ -z "$latest_line" ]; then
                    latest_line="$candidate"
                fi
                if printf '%s' "$candidate" | jq -e --arg preferred_limit_id "$preferred_limit_id" \
                    '.payload.rate_limits.limit_id == $preferred_limit_id' >/dev/null 2>&1; then
                    preferred_line="$candidate"
                    break
                fi
            done < <(tail -r "$session_file" 2>/dev/null)
        fi

        if [ -n "$preferred_line" ]; then
            printf '%s\n' "$preferred_line"
            return 0
        fi

        if [ -n "$latest_line" ]; then
            printf '%s\n' "$latest_line"
            return 0
        fi

        return 1
    fi

    if command -v tac >/dev/null 2>&1; then
        tac "$session_file" | grep -m1 '"token_count"'
    else
        tail -r "$session_file" 2>/dev/null | grep -m1 '"token_count"'
    fi
}

find_recent_limits_line() {
    local session_file line

    while IFS= read -r session_file; do
        [ -n "$session_file" ] || continue

        if command -v tac >/dev/null 2>&1; then
            line=$(
                tac "$session_file" | while IFS= read -r candidate; do
                    if [[ "$candidate" == *'"token_count"'* ]] && \
                       printf '%s' "$candidate" | jq -e '.payload.rate_limits.primary != null' >/dev/null 2>&1; then
                        printf '%s\n' "$candidate"
                        break
                    fi
                done
            )
        else
            line=$(
                tail -r "$session_file" 2>/dev/null | while IFS= read -r candidate; do
                    if [[ "$candidate" == *'"token_count"'* ]] && \
                       printf '%s' "$candidate" | jq -e '.payload.rate_limits.primary != null' >/dev/null 2>&1; then
                        printf '%s\n' "$candidate"
                        break
                    fi
                done
            )
        fi

        if [ -n "$line" ]; then
            printf '%s' "$line"
            return 0
        fi
    done < <(find "$session_base" -name "*.jsonl" -type f 2>/dev/null | sort -r)

    return 1
}

read_hook_state() {
    local cache_file="${CODEX_STATUSLINE_HOOK_CACHE_FILE:-/tmp/codex/statusline-hook-cache.json}"
    local cache_ttl="${CODEX_STATUSLINE_HOOK_TTL:-600}"
    local updated_at now_epoch

    [ "$show_hook_segment" -eq 1 ] || return 1
    [ -f "$cache_file" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    updated_at=$(jq -r '.updated_at // 0' "$cache_file" 2>/dev/null)
    [[ "$updated_at" =~ ^[0-9]+$ ]] || return 1

    now_epoch=$(resolve_now_epoch)
    if [ $(( now_epoch - updated_at )) -gt "$cache_ttl" ] 2>/dev/null; then
        return 1
    fi

    jq -r '.summary // empty' "$cache_file" 2>/dev/null
}

read_notify_state() {
    local cache_file="${CODEX_STATUSLINE_NOTIFY_CACHE_FILE:-/tmp/codex/statusline-notify-cache.json}"
    local cache_ttl="${CODEX_STATUSLINE_NOTIFY_TTL:-600}"
    local updated_at now_epoch

    [ "$show_notify_segment" -eq 1 ] || return 1
    [ -f "$cache_file" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    updated_at=$(jq -r '.updated_at // 0' "$cache_file" 2>/dev/null)
    [[ "$updated_at" =~ ^[0-9]+$ ]] || return 1

    now_epoch=$(resolve_now_epoch)
    if [ $(( now_epoch - updated_at )) -gt "$cache_ttl" ] 2>/dev/null; then
        return 1
    fi

    jq -r '.summary // .message // empty' "$cache_file" 2>/dev/null
}

read_buddy_state() {
    local cache_file="${CODEX_STATUSLINE_BUDDY_CACHE_FILE:-/tmp/codex/statusline-buddy-cache.json}"
    local cache_ttl="${CODEX_STATUSLINE_BUDDY_TTL:-600}"
    local updated_at now_epoch

    [ "$show_buddy_segment" -eq 1 ] || return 1
    [ -f "$cache_file" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    updated_at=$(jq -r '.updated_at // 0' "$cache_file" 2>/dev/null)
    [[ "$updated_at" =~ ^[0-9]+$ ]] || return 1

    now_epoch=$(resolve_now_epoch)
    if [ $(( now_epoch - updated_at )) -gt "$cache_ttl" ] 2>/dev/null; then
        return 1
    fi

    jq -c '{
        status: (.status // ""),
        summary: (.summary // ""),
        source: (.source // "")
    }' "$cache_file" 2>/dev/null
}

parse_token_count_line() {
    local line="$1"

    [ -n "$line" ] || return 1

    printf '%s' "$line" | jq -c '{
        event_ts: .timestamp,
        input: .payload.info.total_token_usage.input_tokens,
        cached: .payload.info.total_token_usage.cached_input_tokens,
        output: .payload.info.total_token_usage.output_tokens,
        total: (.payload.info.last_token_usage.total_tokens // .payload.info.total_token_usage.total_tokens),
        window: .payload.info.model_context_window,
        primary_pct: .payload.rate_limits.primary.used_percent,
        primary_reset: .payload.rate_limits.primary.resets_at,
        secondary_pct: .payload.rate_limits.secondary.used_percent,
        secondary_reset: .payload.rate_limits.secondary.resets_at,
        has_limits: (.payload.rate_limits.primary != null)
    }' 2>/dev/null
}

resolve_limits_cache_file() {
    local session_cache_file="$1"
    local cache_dir

    cache_dir=$(dirname "$session_cache_file")
    printf "%s" "${CODEX_STATUSLINE_LIMITS_CACHE_FILE:-$cache_dir/statusline-last-limits.json}"
}

limits_json_is_usable() {
    local limits_json="$1"
    local now_epoch="$2"
    local primary_reset secondary_reset limit_fields has_limits

    [ -n "$limits_json" ] || return 1
    limit_fields=$(printf '%s' "$limits_json" | jq -r '[
        (.has_limits // false),
        (.primary_reset // 0),
        (.secondary_reset // 0)
    ] | @tsv' 2>/dev/null) || return 1
    IFS=$'\t' read -r has_limits primary_reset secondary_reset <<EOF
$limit_fields
EOF
    [ "$has_limits" = "true" ] || return 1

    if [ "$primary_reset" -gt "$now_epoch" ] 2>/dev/null || [ "$secondary_reset" -gt "$now_epoch" ] 2>/dev/null; then
        return 0
    fi

    return 1
}

read_last_known_limits() {
    local limits_cache_file="$1"
    local now_epoch="$2"
    local cached_limits

    [ -f "$limits_cache_file" ] || return 1

    cached_limits=$(cat "$limits_cache_file" 2>/dev/null)
    limits_json_is_usable "$cached_limits" "$now_epoch" || return 1

    printf '%s' "$cached_limits"
}

write_last_known_limits() {
    local limits_cache_file="$1"
    local limits_json="$2"
    local now_epoch="$3"

    limits_json_is_usable "$limits_json" "$now_epoch" || return 1

    mkdir -p "$(dirname "$limits_cache_file")"
    printf '%s' "$limits_json" > "$limits_cache_file"
}

parse_session_data() {
    local cache_file="${CODEX_STATUSLINE_CACHE_FILE:-/tmp/codex/statusline-session-cache.json}"
    local cache_max_age=10
    local configured_refresh_interval
    local limits_cache_file
    local selected_session_file
    configured_refresh_interval=$(statusline_resolve_positive_int_setting "${CODEX_STATUSLINE_REFRESH_INTERVAL:-$(statusline_toml_get "$config_file" refresh_interval "")}" "")
    [ -n "$configured_refresh_interval" ] && cache_max_age="$configured_refresh_interval"
    mkdir -p /tmp/codex
    limits_cache_file=$(resolve_limits_cache_file "$cache_file")
    selected_session_file=$(find_latest_session)
    [ -n "$selected_session_file" ] || return 1

    if [ -f "$cache_file" ]; then
        local mtime now age cached_session_file
        mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
        now=$(date +%s)
        age=$(( now - mtime ))
        if [ "$age" -lt "$cache_max_age" ]; then
            if [ -n "$session_file_override" ] && command -v jq >/dev/null 2>&1; then
                cached_session_file=$(jq -r '.session_file // empty' "$cache_file" 2>/dev/null)
                if [ "$cached_session_file" = "$selected_session_file" ]; then
                    cat "$cache_file"
                    return 0
                fi
            else
                cat "$cache_file"
                return 0
            fi
        fi
    fi

    local line
    line=$(find_latest_token_count_line_in_file "$selected_session_file")
    [ -z "$line" ] && return 1

    if ! command -v jq >/dev/null 2>&1; then
        return 1
    fi

    local parsed
    local now_epoch
    parsed=$(parse_token_count_line "$line")
    now_epoch=$(date +%s)

    if [ -n "$parsed" ]; then
        parsed=$(printf '%s' "$parsed" | jq -c --arg session_file "$selected_session_file" '. + {session_file: $session_file}' 2>/dev/null)
    fi

    if [ -n "$parsed" ] && [ "$(printf '%s' "$parsed" | jq -r '.has_limits')" = "true" ]; then
        write_last_known_limits "$limits_cache_file" "$parsed" "$now_epoch" || true
    elif [ -n "$parsed" ]; then
        local fallback_line fallback_parsed
        fallback_parsed=$(read_last_known_limits "$limits_cache_file" "$now_epoch" 2>/dev/null || true)

        if [ -z "$fallback_parsed" ]; then
            fallback_line=$(find_recent_limits_line 2>/dev/null || true)
            if [ -n "$fallback_line" ]; then
                fallback_parsed=$(parse_token_count_line "$fallback_line")
                write_last_known_limits "$limits_cache_file" "$fallback_parsed" "$now_epoch" || true
            fi
        fi

        if [ -n "$fallback_parsed" ] && [ "$(printf '%s' "$fallback_parsed" | jq -r '.has_limits')" = "true" ]; then
            parsed=$(
                printf '%s\n%s' "$parsed" "$fallback_parsed" | jq -sc '.[0] + {
                    primary_pct: .[1].primary_pct,
                    primary_reset: .[1].primary_reset,
                    secondary_pct: .[1].secondary_pct,
                    secondary_reset: .[1].secondary_reset,
                    has_limits: .[1].has_limits
                }' 2>/dev/null
            )
        fi
    fi

    if [ -n "$parsed" ]; then
        printf '%s' "$parsed" > "$cache_file"
        printf '%s' "$parsed"
        return 0
    fi
    return 1
}

# ── Shared rendering functions (ported from statusline.sh) ───────

iso_to_epoch() {
    local iso_str="$1"
    local epoch

    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    if [ -n "$epoch" ]; then
        printf "%s" "$epoch"
        return 0
    fi

    local stripped="${iso_str%%.*}"
    stripped="${stripped%%Z}"
    stripped="${stripped%%+*}"
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"

    if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]] || [[ "$iso_str" == *"-00:00"* ]]; then
        epoch=$(env TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    else
        epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)
    fi

    if [ -n "$epoch" ]; then
        printf "%s" "$epoch"
        return 0
    fi

    return 1
}

resolve_now_epoch() {
    if [[ "${CODEX_STATUSLINE_NOW_EPOCH:-}" =~ ^[0-9]+$ ]]; then
        printf "%s" "$CODEX_STATUSLINE_NOW_EPOCH"
        return 0
    fi

    if [ -n "${session_event_epoch:-}" ] && [ "$session_event_epoch" -gt 0 ] 2>/dev/null; then
        printf "%s" "$session_event_epoch"
        return 0
    fi

    date +%s
}

format_epoch_time() {
    local target_epoch="$1"
    local format_string="$2"

    if [ -z "$target_epoch" ] || [ -z "$format_string" ]; then
        return
    fi

    date -r "$target_epoch" +"$format_string" 2>/dev/null || \
    date -d "@$target_epoch" +"$format_string" 2>/dev/null
}

format_tokens() {
    local num=$1
    if [ "$num" -ge 1000000 ]; then
        awk "BEGIN {printf \"%.1fm\", $num / 1000000}"
    elif [ "$num" -ge 1000 ]; then
        awk "BEGIN {printf \"%.0fk\", $num / 1000}"
    else
        printf "%d" "$num"
    fi
}

usage_color() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then
        printf "%s" "$red"
    elif [ "$pct" -ge 70 ]; then
        printf "%s" "$orange"
    elif [ "$pct" -ge 50 ]; then
        printf "%s" "$yellow"
    else
        printf "%s" "$green"
    fi
}

remaining_color() {
    local pct=$1
    if [ "$pct" -le 10 ]; then
        printf "%s" "$red"
    elif [ "$pct" -le 30 ]; then
        printf "%s" "$orange"
    elif [ "$pct" -le 50 ]; then
        printf "%s" "$yellow"
    else
        printf "%s" "$green"
    fi
}

remaining_percent() {
    local used=$1
    local left=$(( 100 - used ))

    if [ "$left" -lt 0 ]; then
        left=0
    fi

    printf "%s" "$left"
}

is_positive_int() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

get_max_width() {
    if is_positive_int "${CODEX_STATUSLINE_MAX_WIDTH:-}"; then
        printf "%s" "$CODEX_STATUSLINE_MAX_WIDTH"
        return
    fi

    if is_positive_int "${COLUMNS:-}"; then
        printf "%s" "$COLUMNS"
        return
    fi

    local cols
    cols=$(tput cols 2>/dev/null)
    if is_positive_int "$cols"; then
        printf "%s" "$cols"
        return
    fi

    printf "100"
}

truncate_middle() {
    local value="$1"
    local limit="$2"
    local length=${#value}

    if [ "$length" -le "$limit" ]; then
        printf "%s" "$value"
        return
    fi

    if [ "$limit" -le 3 ]; then
        printf "..."
        return
    fi

    local left_keep=$(( (limit - 3) / 2 ))
    local right_keep=$(( limit - 3 - left_keep ))
    local right_start=$(( length - right_keep ))

    printf "%s...%s" "${value:0:left_keep}" "${value:right_start}"
}

add_segment() {
    segment_texts+=("$1")
    segment_plains+=("$2")
}

repeat_char() {
    local count="$1"
    local char="$2"
    local result=""

    [ "$count" -le 0 ] && return
    while [ "$count" -gt 0 ]; do
        result="${result}${char}"
        count=$(( count - 1 ))
    done
    printf "%s" "$result"
}

buddy_status_label() {
    case "$1" in
        idle) printf "idle" ;;
        ok) printf "ok" ;;
        done) printf "done" ;;
        blocked) printf "blocked" ;;
        needs_input|needs-input|need_input) printf "needs input" ;;
        *)
            if [ -n "$1" ]; then
                printf "%s" "${1//_/ }"
            fi
            ;;
    esac
}

buddy_status_color() {
    case "$1" in
        idle) printf "%s" "$secondary" ;;
        ok) printf "%s" "$green" ;;
        done) printf "%s" "$teal" ;;
        blocked) printf "%s" "$red" ;;
        needs_input|needs-input|need_input) printf "%s" "$orange" ;;
        *) printf "%s" "$accent" ;;
    esac
}

build_buddy_slot_segment() {
    local max_width="$1"
    local include_summary="${2:-1}"
    local label="buddy ${buddy_status_text}"
    local status_color prefix_text remaining summary_text

    SEG_PLAIN=""
    SEG_TEXT=""

    [ -n "$buddy_status_text" ] || return
    [ "$max_width" -gt 0 ] 2>/dev/null || return

    status_color=$(buddy_status_color "$buddy_status")
    prefix_text="${dim}buddy${reset} ${status_color}${buddy_status_text}${reset}"

    SEG_PLAIN="$label"
    SEG_TEXT="$prefix_text"

    if [ "$include_summary" -ne 1 ] || [ -z "$buddy_summary" ]; then
        return
    fi

    remaining=$(( max_width - ${#label} - 1 ))
    if [ "$remaining" -lt 8 ] 2>/dev/null; then
        return
    fi

    summary_text="$buddy_summary"
    if [ ${#summary_text} -gt "$remaining" ]; then
        summary_text=$(truncate_middle "$summary_text" "$remaining")
    fi

    SEG_PLAIN+=" ${summary_text}"
    SEG_TEXT+=" ${secondary}${summary_text}${reset}"
}

compose_overview_left_segments() {
    local include_eff_segment="${1:-1}"
    local include_hook_overview="${2:-1}"
    local include_notify_overview="${3:-1}"
    local segment_name
    segment_texts=()
    segment_plains=()

    for segment_name in "${ordered_segments[@]}"; do
        case "$segment_name" in
            model)
                segment_enabled "model" || continue
                build_model_segment
                add_segment "$SEG_TEXT" "$SEG_PLAIN"
                ;;
            eff)
                [ "$include_eff_segment" -eq 1 ] || continue
                segment_enabled "eff" || continue
                build_eff_segment
                add_segment "$SEG_TEXT" "$SEG_PLAIN"
                ;;
            ctx)
                segment_enabled "ctx" || continue
                build_ctx_segment
                add_segment "$SEG_TEXT" "$SEG_PLAIN"
                ;;
            hook)
                [ "$include_hook_overview" -eq 1 ] || continue
                [ "$show_hook_segment" -eq 1 ] || continue
                segment_enabled "hook" || continue
                build_hook_segment
                if [ -n "$SEG_PLAIN" ]; then
                    add_segment "$SEG_TEXT" "$SEG_PLAIN"
                fi
                ;;
            notify)
                [ "$include_notify_overview" -eq 1 ] || continue
                [ "$show_notify_segment" -eq 1 ] || continue
                segment_enabled "notify" || continue
                build_notify_segment
                if [ -n "$SEG_PLAIN" ]; then
                    add_segment "$SEG_TEXT" "$SEG_PLAIN"
                fi
                ;;
        esac
    done

    COMPOSED_TEXT=""
    COMPOSED_PLAIN=""
    local idx
    for idx in "${!segment_texts[@]}"; do
        if [ "$idx" -gt 0 ]; then
            COMPOSED_TEXT+="$sep_text"
            COMPOSED_PLAIN+="$sep_plain"
        fi
        COMPOSED_TEXT+="${segment_texts[$idx]}"
        COMPOSED_PLAIN+="${segment_plains[$idx]}"
    done
    COMPOSED_LEN=${#COMPOSED_PLAIN}
}

# ── Segment builders ─────────────────────────────────────────────

build_model_segment() {
    SEG_PLAIN="$model_name"
    SEG_TEXT="${accent}${model_name}${reset}"
}

build_repo_segment() {
    SEG_PLAIN="$display_dir"
    SEG_TEXT="${teal}${display_dir}${reset}"
}

build_branch_segment() {
    SEG_PLAIN=""
    SEG_TEXT=""

    [ -n "$git_branch" ] || return

    local label_prefix="git "
    if [ "$git_display_mode" = "branch" ]; then
        label_prefix="branch:"
    fi
    local branch_name="$git_branch"
    if [ "$branch_truncate_width" -gt 0 ]; then
        local branch_name_limit=$(( branch_truncate_width - ${#label_prefix} ))
        if [ "$branch_name_limit" -le 3 ]; then
            branch_name="..."
        elif [ ${#branch_name} -gt "$branch_name_limit" ]; then
            branch_name=$(truncate_middle "$branch_name" "$branch_name_limit")
        fi
    fi

    SEG_PLAIN="${label_prefix}${branch_name}"
    if [ "$git_display_mode" = "branch" ]; then
        SEG_TEXT="${dim}branch:${reset}${strong}${branch_name}${reset}"
    else
        SEG_TEXT="${dim}git${reset} ${strong}${branch_name}${reset}"
    fi
}

build_git_diff_segment() {
    SEG_PLAIN=""
    SEG_TEXT=""

    if [ "$show_git_diff" -ne 1 ] || [ -z "$git_stat" ]; then
        return
    fi

    local added_part="${git_stat%% *}"
    local deleted_part="${git_stat##* }"
    SEG_PLAIN="(${git_stat})"
    SEG_TEXT="${dim}(${reset}${green}${added_part}${reset} ${red}${deleted_part}${reset}${dim})${reset}"
}

build_ctx_segment() {
    local pct_color
    pct_color=$(usage_color "$pct_used")
    SEG_PLAIN="ctx ${used_tokens}/${total_tokens} ${pct_used}%"
    SEG_TEXT="${dim}ctx${reset} ${primary}${used_tokens}/${total_tokens}${reset} ${bold}${pct_color}${pct_used}%${reset}"
}

build_hook_segment() {
    SEG_PLAIN=""
    SEG_TEXT=""

    [ -n "$hook_summary" ] || return

    SEG_PLAIN="hook ${hook_summary}"
    SEG_TEXT="${dim}hook${reset} ${accent}${hook_summary}${reset}"
}

build_notify_segment() {
    local summary_text="$notify_summary"

    SEG_PLAIN=""
    SEG_TEXT=""

    [ -n "$summary_text" ] || return

    if [ ${#summary_text} -gt 24 ]; then
        summary_text=$(truncate_middle "$summary_text" 24)
    fi

    SEG_PLAIN="notify ${summary_text}"
    SEG_TEXT="${dim}notify${reset} ${teal}${summary_text}${reset}"
}

build_buddy_segment() {
    SEG_PLAIN=""
    SEG_TEXT=""

    [ -n "$buddy_status_text" ] || return

    build_buddy_slot_segment 36 1
}

build_eff_segment() {
    local effort_label effort_text
    case "$effort_level" in
        low)
            effort_label="low"
            effort_text="${strong}low${reset}"
            ;;
        medium)
            effort_label="medium"
            effort_text="${yellow}medium${reset}"
            ;;
        *)
            effort_label="high"
            effort_text="${orange}high${reset}"
            ;;
    esac

    SEG_PLAIN="${effort_label}"
    SEG_TEXT="${effort_text}"
}

build_five_hour_segment() {
    if [ "$usage_available" -ne 1 ]; then
        SEG_PLAIN="5h -"
        SEG_TEXT="${dim}5h${reset} ${secondary}-${reset}"
        return
    fi

    local pct_color pct_text
    pct_text="${five_hour_remaining_pct}% left"
    pct_color=$(remaining_color "$five_hour_remaining_pct")
    SEG_PLAIN="5h ${pct_text}"
    SEG_TEXT="${dim}5h${reset} ${bold}${pct_color}${pct_text}${reset}"
    if [ "$show_five_hour_reset" -eq 1 ] && [ -n "$five_hour_reset" ]; then
        SEG_PLAIN+=" ${five_hour_reset}"
        SEG_TEXT+=" ${secondary}${five_hour_reset}${reset}"
    fi
}

build_seven_day_segment() {
    if [ "$usage_available" -ne 1 ]; then
        SEG_PLAIN="${weekly_label} -"
        SEG_TEXT="${dim}${weekly_label}${reset} ${secondary}-${reset}"
        return
    fi

    local pct_color pct_text
    pct_text="${seven_day_remaining_pct}% left"
    pct_color=$(remaining_color "$seven_day_remaining_pct")
    SEG_PLAIN="${weekly_label} ${pct_text}"
    SEG_TEXT="${dim}${weekly_label}${reset} ${bold}${pct_color}${pct_text}${reset}"
    if [ "$show_seven_day_reset" -eq 1 ] && [ -n "$seven_day_reset" ]; then
        SEG_PLAIN+=" ${seven_day_reset}"
        SEG_TEXT+=" ${secondary}${seven_day_reset}${reset}"
    fi
}

# ── Composition ──────────────────────────────────────────────────

compose_segments() {
    local include_repo_segment="${1:-1}"
    local include_branch_segment="${2:-1}"
    local include_usage_segments="${3:-1}"
    local include_git_diff_segment="${4:-1}"
    local include_buddy_segment="${5:-1}"
    local segment_name
    segment_texts=()
    segment_plains=()
    BRANCH_SEGMENT_LEN=0

    for segment_name in "${ordered_segments[@]}"; do
        case "$segment_name" in
            model)
                segment_enabled "model" || continue
                build_model_segment
                add_segment "$SEG_TEXT" "$SEG_PLAIN"
                ;;
            eff)
                segment_enabled "eff" || continue
                build_eff_segment
                add_segment "$SEG_TEXT" "$SEG_PLAIN"
                ;;
            ctx)
                segment_enabled "ctx" || continue
                build_ctx_segment
                add_segment "$SEG_TEXT" "$SEG_PLAIN"
                ;;
            hook)
                [ "$show_hook_segment" -eq 1 ] || continue
                segment_enabled "hook" || continue
                build_hook_segment
                if [ -n "$SEG_PLAIN" ]; then
                    add_segment "$SEG_TEXT" "$SEG_PLAIN"
                fi
                ;;
            notify)
                [ "$show_notify_segment" -eq 1 ] || continue
                segment_enabled "notify" || continue
                build_notify_segment
                if [ -n "$SEG_PLAIN" ]; then
                    add_segment "$SEG_TEXT" "$SEG_PLAIN"
                fi
                ;;
            buddy)
                [ "$include_buddy_segment" -eq 1 ] || continue
                [ "$show_buddy_segment" -eq 1 ] || continue
                segment_enabled "buddy" || continue
                build_buddy_segment
                if [ -n "$SEG_PLAIN" ]; then
                    add_segment "$SEG_TEXT" "$SEG_PLAIN"
                fi
                ;;
            git)
                segment_enabled "git" || continue
                if [ "$include_repo_segment" -eq 1 ]; then
                    build_repo_segment
                    if [ -n "$SEG_PLAIN" ]; then
                        add_segment "$SEG_TEXT" "$SEG_PLAIN"
                    fi
                fi
                if [ "$include_branch_segment" -eq 1 ]; then
                    build_branch_segment
                    if [ -n "$SEG_PLAIN" ]; then
                        BRANCH_SEGMENT_LEN=${#SEG_PLAIN}
                        add_segment "$SEG_TEXT" "$SEG_PLAIN"
                    fi
                    if [ "$include_git_diff_segment" -eq 1 ]; then
                        build_git_diff_segment
                        if [ -n "$SEG_PLAIN" ]; then
                            add_segment "$SEG_TEXT" "$SEG_PLAIN"
                        fi
                    fi
                fi
                ;;
            5h)
                [ "$include_usage_segments" -eq 1 ] || continue
                segment_enabled "5h" || continue
                build_five_hour_segment
                add_segment "$SEG_TEXT" "$SEG_PLAIN"
                ;;
            7d)
                [ "$include_usage_segments" -eq 1 ] || continue
                [ "$show_seven_day" -eq 1 ] || continue
                segment_enabled "7d" || continue
                build_seven_day_segment
                add_segment "$SEG_TEXT" "$SEG_PLAIN"
                ;;
        esac
    done

    COMPOSED_TEXT=""
    COMPOSED_PLAIN=""
    local idx
    for idx in "${!segment_texts[@]}"; do
        if [ "$idx" -gt 0 ]; then
            COMPOSED_TEXT+="$sep_text"
            COMPOSED_PLAIN+="$sep_plain"
        fi
        COMPOSED_TEXT+="${segment_texts[$idx]}"
        COMPOSED_PLAIN+="${segment_plains[$idx]}"
    done
    COMPOSED_LEN=${#COMPOSED_PLAIN}
}

# ── Width-adaptive rendering ─────────────────────────────────────

render_compact_output() {
    include_usage_summary="$1"
    compose_segments 0 1 "$include_usage_summary" 1

    if [ "$include_usage_summary" -eq 1 ] && [ "$COMPOSED_LEN" -gt "$max_width" ] && [ "$show_seven_day_reset" -eq 1 ]; then
        show_seven_day_reset=0
        compose_segments 0 1 "$include_usage_summary" 1
    fi

    if [ "$include_usage_summary" -eq 1 ] && [ "$COMPOSED_LEN" -gt "$max_width" ] && [ "$show_five_hour_reset" -eq 1 ]; then
        show_five_hour_reset=0
        compose_segments 0 1 "$include_usage_summary" 1
    fi

    if [ "$include_usage_summary" -eq 1 ] && [ "$COMPOSED_LEN" -gt "$max_width" ] && [ "$show_seven_day" -eq 1 ]; then
        show_seven_day=0
        compose_segments 0 1 "$include_usage_summary" 1
    fi

    if [ "$COMPOSED_LEN" -gt "$max_width" ] && [ "$show_git_diff" -eq 1 ]; then
        show_git_diff=0
        compose_segments 0 1 "$include_usage_summary" 1
    fi

    if [ "$COMPOSED_LEN" -gt "$max_width" ] && [ "$BRANCH_SEGMENT_LEN" -gt 0 ]; then
        available_for_branch=$(( max_width - (COMPOSED_LEN - BRANCH_SEGMENT_LEN) ))
        if [ "$available_for_branch" -lt 10 ]; then
            available_for_branch=10
        fi
        branch_truncate_width="$available_for_branch"
        compose_segments 0 1 "$include_usage_summary" 1
    fi

    OUTPUT_TEXT="$COMPOSED_TEXT"
}

build_bars_git_line() {
    local repo_name="$display_dir"
    local branch_name="$git_branch"
    local plain_text text_output

    if [ "$git_display_mode" = "branch" ] && [ -n "$branch_name" ]; then
        plain_text="branch:${branch_name}"
        if [ ${#plain_text} -gt "$max_width" ]; then
            local branch_name_limit=$(( max_width - 7 ))
            if [ "$branch_name_limit" -le 3 ]; then
                branch_name="..."
            elif [ ${#branch_name} -gt "$branch_name_limit" ]; then
                branch_name=$(truncate_middle "$branch_name" "$branch_name_limit")
            fi
            plain_text="branch:${branch_name}"
        fi
        if [ ${#plain_text} -gt "$max_width" ]; then
            plain_text=$(truncate_middle "$plain_text" "$max_width")
        fi
        text_output="${dim}branch:${reset}${secondary}${branch_name}${reset}"
        LINE_PLAIN="$plain_text"
        LINE_TEXT="$text_output"
        return
    fi

    if [ -n "$branch_name" ]; then
        plain_text="${repo_name}@${branch_name}"
        if [ ${#plain_text} -gt "$max_width" ]; then
            local branch_name_limit=$(( max_width - ${#repo_name} - 1 ))
            if [ "$branch_name_limit" -le 3 ]; then
                branch_name="..."
            elif [ ${#branch_name} -gt "$branch_name_limit" ]; then
                branch_name=$(truncate_middle "$branch_name" "$branch_name_limit")
            fi
            plain_text="${repo_name}@${branch_name}"
        fi
        if [ ${#plain_text} -gt "$max_width" ]; then
            plain_text=$(truncate_middle "$plain_text" "$max_width")
        fi
        text_output="${secondary}${repo_name}${reset}${dim}@${reset}${secondary}${branch_name}${reset}"
    else
        plain_text="$repo_name"
        if [ ${#plain_text} -gt "$max_width" ]; then
            plain_text=$(truncate_middle "$plain_text" "$max_width")
        fi
        text_output="${secondary}${plain_text}${reset}"
    fi

    LINE_PLAIN="$plain_text"
    LINE_TEXT="$text_output"
}

render_bars_overview_output() {
    compose_segments 0 0 0 0
    OUTPUT_TEXT="$COMPOSED_TEXT"
}

build_bars_overview_line() {
    local include_eff_segment=1
    local include_hook_overview=1
    local include_notify_overview=1
    local buddy_min_plain buddy_min_text buddy_right_plain buddy_right_text
    local left_plain left_text left_budget gap_width truncated_left

    compose_overview_left_segments "$include_eff_segment" "$include_hook_overview" "$include_notify_overview"
    left_plain="$COMPOSED_PLAIN"
    left_text="$COMPOSED_TEXT"

    if [ "$show_buddy_segment" -ne 1 ] || ! segment_enabled "buddy" || [ -z "$buddy_status_text" ]; then
        LINE_PLAIN="$left_plain"
        LINE_TEXT="$left_text"
        return
    fi

    build_buddy_slot_segment "$max_width" 0
    buddy_min_plain="$SEG_PLAIN"
    buddy_min_text="$SEG_TEXT"

    if [ -z "$buddy_min_plain" ]; then
        LINE_PLAIN="$left_plain"
        LINE_TEXT="$left_text"
        return
    fi

    left_budget=$(( max_width - 2 - ${#buddy_min_plain} ))
    if [ "$left_budget" -lt 0 ]; then
        left_budget=0
    fi

    if [ ${#left_plain} -gt "$left_budget" ] && [ "$include_notify_overview" -eq 1 ]; then
        include_notify_overview=0
        compose_overview_left_segments "$include_eff_segment" "$include_hook_overview" "$include_notify_overview"
        left_plain="$COMPOSED_PLAIN"
        left_text="$COMPOSED_TEXT"
    fi

    if [ ${#left_plain} -gt "$left_budget" ] && [ "$include_hook_overview" -eq 1 ]; then
        include_hook_overview=0
        compose_overview_left_segments "$include_eff_segment" "$include_hook_overview" "$include_notify_overview"
        left_plain="$COMPOSED_PLAIN"
        left_text="$COMPOSED_TEXT"
    fi

    if [ ${#left_plain} -gt "$left_budget" ] && [ "$include_eff_segment" -eq 1 ]; then
        include_eff_segment=0
        compose_overview_left_segments "$include_eff_segment" "$include_hook_overview" "$include_notify_overview"
        left_plain="$COMPOSED_PLAIN"
        left_text="$COMPOSED_TEXT"
    fi

    if [ ${#left_plain} -gt "$left_budget" ]; then
        truncated_left=$(truncate_middle "$left_plain" "$left_budget")
        left_plain="$truncated_left"
        left_text="${secondary}${truncated_left}${reset}"
    fi

    build_buddy_slot_segment "$(( max_width - 2 - ${#left_plain} ))" 1
    buddy_right_plain="$SEG_PLAIN"
    buddy_right_text="$SEG_TEXT"

    if [ -z "$buddy_right_plain" ]; then
        buddy_right_plain="$buddy_min_plain"
        buddy_right_text="$buddy_min_text"
    fi

    gap_width=$(( max_width - ${#left_plain} - ${#buddy_right_plain} ))
    if [ "$gap_width" -lt 2 ]; then
        gap_width=2
    fi

    LINE_PLAIN="${left_plain}$(repeat_char "$gap_width" " ")${buddy_right_plain}"
    LINE_TEXT="${left_text}$(repeat_char "$gap_width" " ")${buddy_right_text}"
}

build_usage_bar_line() {
    local label="$1"
    local pct_value="$2"
    local pct_text="$3"
    local full_time="$4"
    local short_time="$5"
    local time_text="$full_time"
    local base_bar_width=10
    local min_bar_width=4

    if [ "$label" = "5h" ] && [ "$max_width" -le 44 ]; then
        time_text=""
    fi

    if [ "$label" = "$weekly_label" ]; then
        if [ "$max_width" -le 44 ]; then
            time_text="$short_time"
        elif [ "$max_width" -le 52 ] && [ -n "$short_time" ]; then
            time_text="$short_time"
        fi
    fi

    local fixed_width=$(( ${#label} + 1 + ${#pct_text} + 1 + 2 ))
    if [ -n "$time_text" ]; then
        fixed_width=$(( fixed_width + 1 + ${#time_text} ))
    fi

    local bar_width=$base_bar_width
    local available_width=$(( max_width - fixed_width ))
    if [ "$available_width" -lt "$bar_width" ]; then
        bar_width="$available_width"
    fi
    if [ "$bar_width" -lt "$min_bar_width" ]; then
        bar_width="$min_bar_width"
    fi

    local filled_width=0
    if [ "$pct_value" -gt 0 ]; then
        filled_width=$(( pct_value * bar_width / 100 ))
    fi
    if [ "$filled_width" -gt "$bar_width" ]; then
        filled_width="$bar_width"
    fi
    local empty_width=$(( bar_width - filled_width ))

    local filled_plain empty_plain filled_text pct_color time_color label_color
    filled_plain=$(repeat_char "$filled_width" "$bar_filled_char")
    empty_plain=$(repeat_char "$empty_width" "$bar_empty_char")

    if [ "$pct_text" = "--" ]; then
        pct_color="$secondary"
        time_color="$secondary"
        filled_text="${secondary}${filled_plain}${reset}"
    else
        pct_color=$(remaining_color "$pct_value")
        time_color="$secondary"
        filled_text="${pct_color}${filled_plain}${reset}"
    fi
    label_color="$teal"
    [ "$label" = "$weekly_label" ] && label_color="$accent"

    LINE_PLAIN="${label} ${pct_text} [${filled_plain}${empty_plain}]"
    LINE_TEXT="${label_color}${label}${reset} ${bold}${pct_color}${pct_text}${reset} ${dim}[${reset}${filled_text}${track}${empty_plain}${reset}${dim}]${reset}"

    if [ -n "$time_text" ]; then
        LINE_PLAIN+=" ${time_text}"
        LINE_TEXT+=" ${time_color}${time_text}${reset}"
    fi
}

build_usage_unavailable_line() {
    local label="$1"
    LINE_PLAIN="${label} unavailable"
    LINE_TEXT="${dim}${label}${reset} ${secondary}unavailable${reset}"
}

build_bars_line() {
    local line_no="$1"
    local full_five_time="$five_hour_reset"
    local full_seven_time="$seven_day_reset"
    local short_seven_time="$seven_day_date"

    LINE_PLAIN=""
    LINE_TEXT=""

    if [ -n "$full_five_time" ]; then
        full_five_time="${full_five_time} reset"
    fi

    case "$line_no" in
        1)
            [ "$show_bars_git_line" -eq 1 ] || return
            build_bars_git_line
            ;;
        2)
            [ "$show_bars_overview_line" -eq 1 ] || return
            build_bars_overview_line
            ;;
        3)
            segment_enabled "5h" || return
            if [ "$usage_available" -eq 1 ]; then
                build_usage_bar_line "5h" "$five_hour_remaining_pct" "${five_hour_remaining_pct}% left" "$full_five_time" ""
            else
                build_usage_unavailable_line "5h"
            fi
            ;;
        4)
            segment_enabled "7d" || return
            if [ "$usage_available" -eq 1 ]; then
                build_usage_bar_line "$weekly_label" "$seven_day_remaining_pct" "${seven_day_remaining_pct}% left" "$full_seven_time" "$short_seven_time"
            else
                build_usage_unavailable_line "$weekly_label"
            fi
            ;;
    esac
}

render_bars_output() {
    local line_no
    local output_text=""

    for line_no in 1 2 3 4; do
        build_bars_line "$line_no"
        [ -n "$LINE_TEXT" ] || continue
        if [ -n "$output_text" ]; then
            output_text+=$'\n'
        fi
        output_text+="$LINE_TEXT"
    done

    OUTPUT_TEXT="$output_text"
}

# ── Collect data ─────────────────────────────────────────────────

model_name=$(resolve_model)
effort_level=$(resolve_effort)
two_week_time_format=$(resolve_two_week_time_format "${CODEX_STATUSLINE_TWO_WEEK_TIME_FORMAT:-$(statusline_toml_get "$config_file" two_week_time_format "")}")
show_bars_git_line=$(statusline_resolve_bool_setting "${CODEX_STATUSLINE_SHOW_GIT_LINE:-$(statusline_toml_get "$config_file" show_git_line "")}" "1")
show_bars_overview_line=$(statusline_resolve_bool_setting "${CODEX_STATUSLINE_SHOW_OVERVIEW_LINE:-$(statusline_toml_get "$config_file" show_overview_line "")}" "1")
show_hook_segment=$(statusline_resolve_bool_setting "${CODEX_STATUSLINE_SHOW_HOOK_SEGMENT:-$(statusline_toml_get "$config_file" show_hook_segment "")}" "0")
show_notify_segment=$(statusline_resolve_bool_setting "${CODEX_STATUSLINE_SHOW_NOTIFY_SEGMENT:-$(statusline_toml_get "$config_file" show_notify_segment "")}" "0")
show_buddy_segment=$(statusline_resolve_bool_setting "${CODEX_STATUSLINE_SHOW_BUDDY_SEGMENT:-$(statusline_toml_get "$config_file" show_buddy_segment "")}" "0")
initialize_segment_order

display_dir="${target_dir##*/}"
git_branch=""
git_stat=""
if git -C "$target_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(git -C "$target_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
    git_stat=$(
        {
            git -C "$target_dir" diff --numstat 2>/dev/null
            git -C "$target_dir" diff --cached --numstat 2>/dev/null
        } | awk '{if ($1 ~ /^[0-9]+$/) a+=$1; if ($2 ~ /^[0-9]+$/) d+=$2} END {if (a+d>0) printf "+%d -%d", a, d}'
    )
fi

# Parse session data for token usage and rate limits
usage_available=0
show_seven_day=1
show_five_hour_reset=0
show_seven_day_reset=0
show_git_diff=0
branch_truncate_width=0

five_hour_pct=0
five_hour_remaining_pct=0
five_hour_reset=""
seven_day_pct=0
seven_day_remaining_pct=0
seven_day_reset=""
seven_day_date=""

ctx_total=0
ctx_window=0
pct_used=0
used_tokens="0"
total_tokens="0"

session_json=$(parse_session_data 2>/dev/null) || session_json=""
if [ -n "$session_json" ]; then
    session_fields=$(printf '%s' "$session_json" | jq -r '[
        (.event_ts // ""),
        (.total // 0),
        (.window // 0),
        (.has_limits // false),
        (.primary_pct // 0),
        (.primary_reset // 0),
        (.secondary_pct // 0),
        (.secondary_reset // 0)
    ] | @tsv' 2>/dev/null)
    IFS=$'\t' read -r session_event_ts ctx_total ctx_window has_limits five_hour_utilization five_hour_reset_epoch seven_day_utilization seven_day_reset_epoch <<EOF
$session_fields
EOF
    [ -n "$ctx_total" ] || ctx_total=0
    [ -n "$ctx_window" ] || ctx_window=0
    [ -n "$has_limits" ] || has_limits="false"
    [ -n "$five_hour_utilization" ] || five_hour_utilization=0
    [ -n "$five_hour_reset_epoch" ] || five_hour_reset_epoch=0
    [ -n "$seven_day_utilization" ] || seven_day_utilization=0
    [ -n "$seven_day_reset_epoch" ] || seven_day_reset_epoch=0
    session_event_epoch=$(iso_to_epoch "$session_event_ts" 2>/dev/null) || session_event_epoch=""
    if [ "$ctx_window" -gt 0 ] 2>/dev/null; then
        pct_used=$(( ctx_total * 100 / ctx_window ))
    fi
    used_tokens=$(format_tokens "$ctx_total")
    total_tokens=$(format_tokens "$ctx_window")

    if [ "$has_limits" = "true" ]; then
        usage_available=1
        five_hour_pct=$(LC_NUMERIC=C awk -v value="${five_hour_utilization:-0}" 'BEGIN {printf "%.0f", value + 0}')
        five_hour_remaining_pct=$(remaining_percent "$five_hour_pct")
        seven_day_pct=$(LC_NUMERIC=C awk -v value="${seven_day_utilization:-0}" 'BEGIN {printf "%.0f", value + 0}')
        seven_day_remaining_pct=$(remaining_percent "$seven_day_pct")

        now=$(resolve_now_epoch)
        if [ "$five_hour_reset_epoch" -gt "$now" ] 2>/dev/null; then
            five_hour_reset=$(date -r "$five_hour_reset_epoch" +"%H:%M" 2>/dev/null || \
                              date -d "@$five_hour_reset_epoch" +"%H:%M" 2>/dev/null) || true
            [ -n "$five_hour_reset" ] && show_five_hour_reset=1
        fi
        if [ "$seven_day_reset_epoch" -gt "$now" ] 2>/dev/null; then
            seven_day_reset=$(format_epoch_time "$seven_day_reset_epoch" "$two_week_time_format")
            seven_day_date=$(format_epoch_time "$seven_day_reset_epoch" "$short_seven_day_date_format")
            [ -n "$seven_day_reset" ] && show_seven_day_reset=1
        fi
    fi
fi

hook_summary="$(read_hook_state 2>/dev/null || true)"
notify_summary="$(read_notify_state 2>/dev/null || true)"
buddy_state="$(read_buddy_state 2>/dev/null || true)"
buddy_status=""
buddy_status_text=""
buddy_summary=""
if [ -n "$buddy_state" ]; then
    buddy_status=$(printf '%s' "$buddy_state" | jq -r '.status // empty' 2>/dev/null)
    buddy_status_text=$(buddy_status_label "$buddy_status")
    buddy_summary=$(printf '%s' "$buddy_state" | jq -r '.summary // empty' 2>/dev/null)
fi

[ -n "$git_stat" ] && show_git_diff=1
max_width=$(get_max_width)

# --line N: output a single line from bars layout (1=git, 2=overview, 3=5h, 4=weekly)
if [ "$line_select" -gt 0 ] 2>/dev/null; then
    build_bars_line "$line_select"
    line_out="$LINE_TEXT"
    if [ "$output_format" = "tmux" ]; then
        printf "%s" "$line_out"
    else
        printf "%b" "$line_out"
    fi
    exit 0
fi

if [ "$layout_name" = "bars" ]; then
    render_bars_output
else
    render_compact_output 1
fi

if [ "$output_format" = "tmux" ]; then
    printf "%s" "$OUTPUT_TEXT"
else
    printf "%b" "$OUTPUT_TEXT"
fi
exit 0
