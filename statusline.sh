#!/bin/bash

set -f

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

# ANSI palette tuned for dim terminal chrome with one strong accent.
accent='\033[38;2;77;166;255m'
teal='\033[38;2;77;175;176m'
branch='\033[38;2;196;208;212m'
red='\033[38;2;255;85;85m'
orange='\033[38;2;255;176;85m'
yellow='\033[38;2;230;200;0m'
green='\033[38;2;0;160;0m'
white='\033[38;2;228;232;234m'
dim='\033[2m'
reset='\033[0m'

sep_plain=' | '
sep_text=" ${dim}|${reset} "

SEG_TEXT=""
SEG_PLAIN=""
COMPOSED_TEXT=""
COMPOSED_PLAIN=""
COMPOSED_LEN=0
GIT_SEGMENT_LEN=0

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

is_positive_int() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

get_max_width() {
    if is_positive_int "${CLAUDE_CODE_STATUSLINE_MAX_WIDTH:-}"; then
        printf "%s" "$CLAUDE_CODE_STATUSLINE_MAX_WIDTH"
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

compose_segments() {
    segment_texts=()
    segment_plains=()
    GIT_SEGMENT_LEN=0

    build_model_segment
    add_segment "$SEG_TEXT" "$SEG_PLAIN"

    build_git_segment
    if [ -n "$SEG_PLAIN" ]; then
        GIT_SEGMENT_LEN=${#SEG_PLAIN}
        add_segment "$SEG_TEXT" "$SEG_PLAIN"
    fi

    build_ctx_segment
    add_segment "$SEG_TEXT" "$SEG_PLAIN"

    build_eff_segment
    add_segment "$SEG_TEXT" "$SEG_PLAIN"

    build_five_hour_segment
    add_segment "$SEG_TEXT" "$SEG_PLAIN"

    if [ "$show_seven_day" -eq 1 ]; then
        build_seven_day_segment
        add_segment "$SEG_TEXT" "$SEG_PLAIN"
    fi

    if [ "$show_extra" -eq 1 ]; then
        build_extra_segment
        if [ -n "$SEG_PLAIN" ]; then
            add_segment "$SEG_TEXT" "$SEG_PLAIN"
        fi
    fi

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

build_model_segment() {
    SEG_PLAIN="$model_name"
    SEG_TEXT="${accent}${model_name}${reset}"
}

build_git_segment() {
    SEG_PLAIN=""
    SEG_TEXT=""

    if [ -z "$cwd" ]; then
        return
    fi

    local base_plain="$display_dir"
    if [ -n "$git_branch" ]; then
        base_plain="${display_dir}@${git_branch}"
    fi

    if [ "$show_git_diff" -eq 1 ] && [ -n "$git_stat" ]; then
        base_plain="${base_plain} (${git_stat})"
    fi

    if [ "$git_truncate_width" -gt 0 ] && [ ${#base_plain} -gt "$git_truncate_width" ]; then
        local truncated
        truncated=$(truncate_middle "$base_plain" "$git_truncate_width")
        SEG_PLAIN="$truncated"
        SEG_TEXT="${teal}${truncated}${reset}"
        return
    fi

    SEG_PLAIN="$base_plain"
    SEG_TEXT="${teal}${display_dir}${reset}"
    if [ -n "$git_branch" ]; then
        SEG_TEXT+="${dim}@${reset}${branch}${git_branch}${reset}"
    fi
    if [ "$show_git_diff" -eq 1 ] && [ -n "$git_stat" ]; then
        local added_part="${git_stat%% *}"
        local deleted_part="${git_stat##* }"
        SEG_TEXT+=" ${dim}(${reset}${green}${added_part}${reset} ${red}${deleted_part}${reset}${dim})${reset}"
    fi
}

build_ctx_segment() {
    local pct_color
    pct_color=$(usage_color "$pct_used")
    SEG_PLAIN="ctx ${used_tokens}/${total_tokens} ${pct_used}%"
    SEG_TEXT="${dim}ctx${reset} ${white}${used_tokens}/${total_tokens}${reset} ${pct_color}${pct_used}%${reset}"
}

build_eff_segment() {
    local effort_label effort_text
    case "$effort_level" in
        low)
            effort_label="low"
            effort_text="${branch}low${reset}"
            ;;
        medium)
            effort_label="med"
            effort_text="${yellow}med${reset}"
            ;;
        *)
            effort_label="high"
            effort_text="${orange}high${reset}"
            ;;
    esac

    SEG_PLAIN="eff ${effort_label}"
    SEG_TEXT="${dim}eff${reset} ${effort_text}"
}

build_five_hour_segment() {
    if [ "$usage_available" -ne 1 ]; then
        SEG_PLAIN="5h -"
        SEG_TEXT="${dim}5h${reset} ${dim}-${reset}"
        return
    fi

    local pct_color
    pct_color=$(usage_color "$five_hour_pct")
    SEG_PLAIN="5h ${five_hour_pct}%"
    SEG_TEXT="${dim}5h${reset} ${pct_color}${five_hour_pct}%${reset}"
    if [ "$show_five_hour_reset" -eq 1 ] && [ -n "$five_hour_reset" ]; then
        SEG_PLAIN+=" ${five_hour_reset}"
        SEG_TEXT+=" ${dim}${five_hour_reset}${reset}"
    fi
}

build_seven_day_segment() {
    if [ "$usage_available" -ne 1 ]; then
        SEG_PLAIN="7d -"
        SEG_TEXT="${dim}7d${reset} ${dim}-${reset}"
        return
    fi

    local pct_color
    pct_color=$(usage_color "$seven_day_pct")
    SEG_PLAIN="7d ${seven_day_pct}%"
    SEG_TEXT="${dim}7d${reset} ${pct_color}${seven_day_pct}%${reset}"
    if [ "$show_seven_day_reset" -eq 1 ] && [ -n "$seven_day_reset" ]; then
        SEG_PLAIN+=" ${seven_day_reset}"
        SEG_TEXT+=" ${dim}${seven_day_reset}${reset}"
    fi
}

build_extra_segment() {
    SEG_PLAIN=""
    SEG_TEXT=""

    if [ "$extra_enabled" != "true" ]; then
        return
    fi

    if [ -n "$extra_used" ] && [ -n "$extra_limit" ] && [[ "$extra_used" != *'$'* ]] && [[ "$extra_limit" != *'$'* ]]; then
        SEG_PLAIN="extra \$${extra_used}/\$${extra_limit}"
        SEG_TEXT="${dim}extra${reset} ${white}\$${extra_used}/\$${extra_limit}${reset}"
        return
    fi

    SEG_PLAIN="extra enabled"
    SEG_TEXT="${dim}extra${reset} ${branch}enabled${reset}"
}

get_oauth_token() {
    local token=""

    if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        printf "%s" "$CLAUDE_CODE_OAUTH_TOKEN"
        return 0
    fi

    if command -v security >/dev/null 2>&1; then
        local blob
        blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                printf "%s" "$token"
                return 0
            fi
        fi
    fi

    local creds_file="${HOME}/.claude/.credentials.json"
    if [ -f "$creds_file" ]; then
        token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
        if [ -n "$token" ] && [ "$token" != "null" ]; then
            printf "%s" "$token"
            return 0
        fi
    fi

    if command -v secret-tool >/dev/null 2>&1; then
        local blob
        blob=$(timeout 2 secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
        if [ -n "$blob" ]; then
            token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [ -n "$token" ] && [ "$token" != "null" ]; then
                printf "%s" "$token"
                return 0
            fi
        fi
    fi

    printf ""
}

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

format_reset_time() {
    local iso_str="$1"
    local style="$2"
    [ -z "$iso_str" ] || [ "$iso_str" = "null" ] && return

    local epoch
    epoch=$(iso_to_epoch "$iso_str")
    [ -z "$epoch" ] && return

    local formatted=""
    case "$style" in
        time)
            formatted=$(date -d "@$epoch" +"%H:%M" 2>/dev/null) || \
            formatted=$(date -j -r "$epoch" +"%H:%M" 2>/dev/null)
            ;;
        datetime)
            formatted=$(date -d "@$epoch" +"%b %-d %H:%M" 2>/dev/null) || \
            formatted=$(date -j -r "$epoch" +"%b %-d %H:%M" 2>/dev/null)
            ;;
        *)
            formatted=$(date -d "@$epoch" +"%b %-d" 2>/dev/null) || \
            formatted=$(date -j -r "$epoch" +"%b %-d" 2>/dev/null)
            ;;
    esac

    if [ -n "$formatted" ]; then
        formatted=$(printf "%s" "$formatted" | sed -E 's/(^| )0([0-9]:)/\1\2/g')
    fi

    [ -n "$formatted" ] && printf "%s" "$formatted"
}

model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')

size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
[ "$size" -eq 0 ] 2>/dev/null && size=200000

input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
current=$(( input_tokens + cache_create + cache_read ))

used_tokens=$(format_tokens "$current")
total_tokens=$(format_tokens "$size")

if [ "$size" -gt 0 ]; then
    pct_used=$(( current * 100 / size ))
else
    pct_used=0
fi

settings_path="$HOME/.claude/settings.json"
effort_level="medium"
if [ -n "$CLAUDE_CODE_EFFORT_LEVEL" ]; then
    effort_level="$CLAUDE_CODE_EFFORT_LEVEL"
elif [ -f "$settings_path" ]; then
    effort_val=$(jq -r '.effortLevel // empty' "$settings_path" 2>/dev/null)
    [ -n "$effort_val" ] && effort_level="$effort_val"
fi

cwd=$(echo "$input" | jq -r '.cwd // empty')
display_dir=""
git_branch=""
git_stat=""
if [ -n "$cwd" ]; then
    display_dir="${cwd##*/}"
    git_branch=$(git -C "${cwd}" rev-parse --abbrev-ref HEAD 2>/dev/null)
    git_stat=$(
        {
            git -C "${cwd}" diff --numstat 2>/dev/null
            git -C "${cwd}" diff --cached --numstat 2>/dev/null
        } | awk '{if ($1 ~ /^[0-9]+$/) a+=$1; if ($2 ~ /^[0-9]+$/) d+=$2} END {if (a+d>0) printf "+%d -%d", a, d}'
    )
fi

cache_file="/tmp/claude/statusline-usage-cache.json"
cache_max_age=60
mkdir -p /tmp/claude

needs_refresh=true
usage_data=""

if [ -f "$cache_file" ]; then
    cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
    now=$(date +%s)
    cache_age=$(( now - cache_mtime ))
    if [ "$cache_age" -lt "$cache_max_age" ]; then
        needs_refresh=false
    fi
    usage_data=$(cat "$cache_file" 2>/dev/null)
fi

if $needs_refresh; then
    touch "$cache_file" 2>/dev/null
    token=$(get_oauth_token)
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        response=$(curl -s --max-time 10 \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $token" \
            -H "anthropic-beta: oauth-2025-04-20" \
            -H "User-Agent: claude-code/2.1.34" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
            usage_data="$response"
            echo "$response" > "$cache_file"
        fi
    fi
fi

usage_available=0
show_seven_day=1
show_extra=0
show_five_hour_reset=0
show_seven_day_reset=0
show_git_diff=0
git_truncate_width=0

five_hour_pct=0
five_hour_reset=""
seven_day_pct=0
seven_day_reset=""
extra_enabled="false"
extra_used=""
extra_limit=""

if [ -n "$usage_data" ] && echo "$usage_data" | jq -e '.five_hour' >/dev/null 2>&1; then
    usage_available=1
    five_hour_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
    five_hour_reset_iso=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
    five_hour_reset=$(format_reset_time "$five_hour_reset_iso" "time")
    [ -n "$five_hour_reset" ] && show_five_hour_reset=1

    seven_day_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
    seven_day_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
    seven_day_reset=$(format_reset_time "$seven_day_reset_iso" "datetime")
    [ -n "$seven_day_reset" ] && show_seven_day_reset=1

    extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
    if [ "$extra_enabled" = "true" ]; then
        extra_used=$(echo "$usage_data" | jq -r '.extra_usage.used_credits // 0' | LC_NUMERIC=C awk '{printf "%.2f", $1/100}')
        extra_limit=$(echo "$usage_data" | jq -r '.extra_usage.monthly_limit // 0' | LC_NUMERIC=C awk '{printf "%.2f", $1/100}')
        show_extra=1
    fi
fi

[ -n "$git_stat" ] && show_git_diff=1
max_width=$(get_max_width)

compose_segments

if [ "$COMPOSED_LEN" -gt "$max_width" ] && [ "$show_extra" -eq 1 ]; then
    show_extra=0
    compose_segments
fi

if [ "$COMPOSED_LEN" -gt "$max_width" ] && [ "$show_seven_day_reset" -eq 1 ]; then
    show_seven_day_reset=0
    compose_segments
fi

if [ "$COMPOSED_LEN" -gt "$max_width" ] && [ "$show_five_hour_reset" -eq 1 ]; then
    show_five_hour_reset=0
    compose_segments
fi

if [ "$COMPOSED_LEN" -gt "$max_width" ] && [ "$show_git_diff" -eq 1 ]; then
    show_git_diff=0
    compose_segments
fi

if [ "$COMPOSED_LEN" -gt "$max_width" ] && [ "$show_seven_day" -eq 1 ]; then
    show_seven_day=0
    compose_segments
fi

if [ "$COMPOSED_LEN" -gt "$max_width" ] && [ "$GIT_SEGMENT_LEN" -gt 0 ]; then
    available_for_git=$(( max_width - (COMPOSED_LEN - GIT_SEGMENT_LEN) ))
    if [ "$available_for_git" -lt 3 ]; then
        available_for_git=3
    fi
    git_truncate_width="$available_for_git"
    compose_segments
fi

printf "%b" "$COMPOSED_TEXT"
exit 0
