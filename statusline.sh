#!/bin/bash

set -f

script_dir="$(cd "$(dirname "$0")" && pwd)"
common_script="$script_dir/codex_statusline_common.sh"
if [ ! -f "$common_script" ]; then
    printf 'missing shared helper: %s\n' "$common_script" >&2
    exit 1
fi
# shellcheck source=./codex_statusline_common.sh
. "$common_script"

input=$(cat)

if [ -z "$input" ]; then
    printf "Claude"
    exit 0
fi

settings_path="$HOME/.claude/settings.json"
theme_name=$(statusline_resolve_json_setting "$settings_path" "default" \
    STATUSLINE_THEME \
    CLAUDE_CODE_STATUSLINE_THEME)
layout_name=$(statusline_resolve_json_setting "$settings_path" "compact" \
    STATUSLINE_MODE \
    CLAUDE_CODE_STATUSLINE_LAYOUT)
bar_style_name=$(statusline_resolve_json_setting "$settings_path" "ascii" \
    STATUSLINE_BAR_STYLE \
    CLAUDE_CODE_STATUSLINE_BAR_STYLE)
claude_statusline_max_width=$(statusline_resolve_json_setting "$settings_path" "" \
    STATUSLINE_MAX_WIDTH \
    CLAUDE_CODE_STATUSLINE_MAX_WIDTH)
seven_day_time_requested=$(statusline_resolve_json_setting "$settings_path" "" \
    STATUSLINE_DAILY_TIME_FORMAT \
    STATUSLINE_SEVEN_DAY_TIME_FORMAT \
    CLAUDE_CODE_STATUSLINE_SEVEN_DAY_TIME_FORMAT)
show_bars_git_line=$(statusline_resolve_json_bool_setting "$settings_path" "1" \
    STATUSLINE_SHOW_GIT_LINE \
    CLAUDE_CODE_STATUSLINE_SHOW_GIT_LINE)
show_bars_overview_line=$(statusline_resolve_json_bool_setting "$settings_path" "1" \
    STATUSLINE_SHOW_OVERVIEW_LINE \
    CLAUDE_CODE_STATUSLINE_SHOW_OVERVIEW_LINE)
show_hourly_bar=$(statusline_resolve_json_bool_setting "$settings_path" "1" \
    STATUSLINE_SHOW_HOURLY_BAR \
    CLAUDE_CODE_STATUSLINE_SHOW_HOURLY_BAR)
show_daily_bar=$(statusline_resolve_json_bool_setting "$settings_path" "1" \
    STATUSLINE_SHOW_DAILY_BAR \
    CLAUDE_CODE_STATUSLINE_SHOW_DAILY_BAR)
case "$layout_name" in
    bars|compact) ;;
    *) layout_name="compact" ;;
esac
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

# ANSI palette tuned for dim terminal chrome with one strong accent.
case "$theme_name" in
    forest)
        accent='\033[38;2;120;196;120m'
        teal='\033[38;2;94;170;150m'
        branch='\033[38;2;214;224;205m'
        muted='\033[38;2;132;144;124m'
        red='\033[38;2;224;108;117m'
        orange='\033[38;2;214;170;84m'
        yellow='\033[38;2;198;183;101m'
        green='\033[38;2;120;196;120m'
        white='\033[38;2;234;238;228m'
        ;;
    dracula)
        accent='\033[38;2;189;147;249m'
        teal='\033[38;2;139;233;253m'
        branch='\033[38;2;248;248;242m'
        muted='\033[38;2;98;114;164m'
        red='\033[38;2;255;85;85m'
        orange='\033[38;2;255;184;108m'
        yellow='\033[38;2;241;250;140m'
        green='\033[38;2;80;250;123m'
        white='\033[38;2;248;248;242m'
        ;;
    monokai)
        accent='\033[38;2;102;217;239m'
        teal='\033[38;2;166;226;46m'
        branch='\033[38;2;230;219;116m'
        muted='\033[38;2;117;113;94m'
        red='\033[38;2;249;38;114m'
        orange='\033[38;2;253;151;31m'
        yellow='\033[38;2;230;219;116m'
        green='\033[38;2;166;226;46m'
        white='\033[38;2;248;248;242m'
        ;;
    solarized)
        accent='\033[38;2;38;139;210m'
        teal='\033[38;2;42;161;152m'
        branch='\033[38;2;147;161;161m'
        muted='\033[38;2;88;110;117m'
        red='\033[38;2;220;50;47m'
        orange='\033[38;2;203;75;22m'
        yellow='\033[38;2;181;137;0m'
        green='\033[38;2;133;153;0m'
        white='\033[38;2;238;232;213m'
        ;;
    ocean)
        accent='\033[38;2;0;188;212m'
        teal='\033[38;2;0;151;167m'
        branch='\033[38;2;178;235;242m'
        muted='\033[38;2;120;144;156m'
        red='\033[38;2;239;83;80m'
        orange='\033[38;2;255;152;0m'
        yellow='\033[38;2;255;213;79m'
        green='\033[38;2;102;187;106m'
        white='\033[38;2;224;247;250m'
        ;;
    sunset)
        accent='\033[38;2;255;138;101m'
        teal='\033[38;2;255;183;77m'
        branch='\033[38;2;255;204;128m'
        muted='\033[38;2;161;136;127m'
        red='\033[38;2;239;83;80m'
        orange='\033[38;2;255;112;66m'
        yellow='\033[38;2;255;213;79m'
        green='\033[38;2;174;213;129m'
        white='\033[38;2;255;243;224m'
        ;;
    amber)
        accent='\033[38;2;255;193;7m'
        teal='\033[38;2;220;184;106m'
        branch='\033[38;2;240;230;200m'
        muted='\033[38;2;158;148;119m'
        red='\033[38;2;232;98;92m'
        orange='\033[38;2;232;152;62m'
        yellow='\033[38;2;212;170;50m'
        green='\033[38;2;140;179;105m'
        white='\033[38;2;245;240;224m'
        ;;
    rose)
        accent='\033[38;2;244;143;177m'
        teal='\033[38;2;206;147;216m'
        branch='\033[38;2;248;215;224m'
        muted='\033[38;2;173;139;159m'
        red='\033[38;2;239;83;80m'
        orange='\033[38;2;255;138;101m'
        yellow='\033[38;2;255;213;79m'
        green='\033[38;2;165;214;167m'
        white='\033[38;2;253;232;239m'
        ;;
    *)
        accent='\033[38;2;77;166;255m'
        teal='\033[38;2;77;175;176m'
        branch='\033[38;2;196;208;212m'
        muted='\033[38;2;115;132;139m'
        red='\033[38;2;255;85;85m'
        orange='\033[38;2;255;176;85m'
        yellow='\033[38;2;230;200;0m'
        green='\033[38;2;0;160;0m'
        white='\033[38;2;228;232;234m'
        ;;
esac
dim='\033[2m'
reset='\033[0m'

sep_plain=' | '
sep_text=" ${dim}|${reset} "
default_seven_day_time_format='%m %d %H:%M'
short_seven_day_date_format='%m %d'

SEG_TEXT=""
SEG_PLAIN=""
COMPOSED_TEXT=""
COMPOSED_PLAIN=""
COMPOSED_LEN=0
GIT_SEGMENT_LEN=0
OUTPUT_TEXT=""
LINE_TEXT=""
LINE_PLAIN=""
include_usage_summary=1

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

is_valid_seven_day_time_format() {
    local value="$1"
    [[ "$value" =~ ^(%[yYmdHMbB]|[[:space:]/:-])+$ ]]
}

resolve_seven_day_time_format() {
    local requested="$1"

    if [ -n "$requested" ] && is_valid_seven_day_time_format "$requested"; then
        printf "%s" "$requested"
        return
    fi

    printf "%s" "$default_seven_day_time_format"
}

is_positive_int() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

get_max_width() {
    if is_positive_int "${claude_statusline_max_width:-}"; then
        printf "%s" "$claude_statusline_max_width"
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

    if [ "$include_usage_summary" -eq 1 ]; then
        build_five_hour_segment
        add_segment "$SEG_TEXT" "$SEG_PLAIN"

        if [ "$show_seven_day" -eq 1 ]; then
            build_seven_day_segment
            add_segment "$SEG_TEXT" "$SEG_PLAIN"
        fi
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

build_usage_bar_line() {
    local label="$1"
    local pct_value="$2"
    local pct_text="$3"
    local full_time="$4"
    local short_time="$5"
    local time_text="$full_time"
    local base_bar_width=10
    local min_bar_width=4
    local min_readable_bar_width=8

    if [ "$label" = "5h" ] && [ "$max_width" -le 44 ]; then
        time_text=""
    fi

    if [ "$label" = "7d" ]; then
        if [ "$max_width" -le 44 ]; then
            time_text="$short_time"
        elif [ "$max_width" -le 52 ] && [ -n "$short_time" ]; then
            time_text="$short_time"
        fi
    fi

    local fixed_width available_width
    fixed_width=$(( ${#label} + 1 + ${#pct_text} + 1 + 2 ))
    if [ -n "$time_text" ]; then
        fixed_width=$(( fixed_width + 1 + ${#time_text} ))
    fi
    available_width=$(( max_width - fixed_width ))

    if [ "$available_width" -lt "$min_readable_bar_width" ] && [ -n "$time_text" ]; then
        time_text=""
        fixed_width=$(( ${#label} + 1 + ${#pct_text} + 1 + 2 ))
        available_width=$(( max_width - fixed_width ))
    fi

    if [ "$available_width" -lt "$min_readable_bar_width" ]; then
        LINE_PLAIN=""
        LINE_TEXT=""
        return
    fi

    local bar_width=$base_bar_width
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

    local filled_plain empty_plain filled_text pct_color time_color
    filled_plain=$(repeat_char "$filled_width" "$bar_filled_char")
    empty_plain=$(repeat_char "$empty_width" "$bar_empty_char")

    if [ "$pct_text" = "--" ]; then
        pct_color="$branch"
        time_color="$branch"
        filled_text="${muted}${filled_plain}${reset}"
    else
        pct_color=$(usage_color "$pct_value")
        time_color="$muted"
        filled_text="${pct_color}${filled_plain}${reset}"
    fi

    LINE_PLAIN="${label} ${pct_text} [${filled_plain}${empty_plain}]"
    LINE_TEXT="${dim}${label}${reset} ${pct_color}${pct_text}${reset} ${dim}[${reset}${filled_text}${muted}${empty_plain}${reset}${dim}]${reset}"

    if [ -n "$time_text" ]; then
        LINE_PLAIN+=" ${time_text}"
        LINE_TEXT+=" ${time_color}${time_text}${reset}"
    fi
}

build_bars_git_line() {
    LINE_PLAIN=""
    LINE_TEXT=""

    [ -n "$display_dir" ] || return

    local repo_name="$display_dir"
    local branch_name="$git_branch"
    local plain_text text_output

    if [ -n "$branch_name" ]; then
        local combined_plain
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
        combined_plain="${repo_name}@${branch_name}"
        if [ "$plain_text" != "$combined_plain" ]; then
            text_output="${muted}${plain_text}${reset}"
        else
            text_output="${muted}${repo_name}${reset}${dim}@${reset}${muted}${branch_name}${reset}"
        fi
    else
        plain_text="$repo_name"
        if [ ${#plain_text} -gt "$max_width" ]; then
            plain_text=$(truncate_middle "$plain_text" "$max_width")
        fi
        text_output="${muted}${plain_text}${reset}"
    fi

    LINE_PLAIN="$plain_text"
    LINE_TEXT="$text_output"
}

build_bars_overview_line() {
    local overview_text=""
    local overview_plain=""

    build_model_segment
    overview_text="$SEG_TEXT"
    overview_plain="$SEG_PLAIN"

    build_eff_segment
    overview_text+="$sep_text$SEG_TEXT"
    overview_plain+="$sep_plain$SEG_PLAIN"

    build_ctx_segment
    overview_text+="$sep_text$SEG_TEXT"
    overview_plain+="$sep_plain$SEG_PLAIN"

    LINE_TEXT="$overview_text"
    LINE_PLAIN="$overview_plain"
}

append_output_line() {
    local next_line="$1"

    [ -n "$next_line" ] || return

    if [ -n "$OUTPUT_TEXT" ]; then
        OUTPUT_TEXT="${OUTPUT_TEXT}"$'\n'"${next_line}"
        return
    fi

    OUTPUT_TEXT="$next_line"
}

render_compact_output() {
    include_usage_summary="$1"
    compose_segments

    if [ "$COMPOSED_LEN" -gt "$max_width" ] && [ "$show_extra" -eq 1 ]; then
        show_extra=0
        compose_segments
    fi

    if [ "$include_usage_summary" -eq 1 ] && [ "$COMPOSED_LEN" -gt "$max_width" ] && [ "$show_seven_day_reset" -eq 1 ]; then
        show_seven_day_reset=0
        compose_segments
    fi

    if [ "$include_usage_summary" -eq 1 ] && [ "$COMPOSED_LEN" -gt "$max_width" ] && [ "$show_five_hour_reset" -eq 1 ]; then
        show_five_hour_reset=0
        compose_segments
    fi

    if [ "$COMPOSED_LEN" -gt "$max_width" ] && [ "$show_git_diff" -eq 1 ]; then
        show_git_diff=0
        compose_segments
    fi

    if [ "$include_usage_summary" -eq 1 ] && [ "$COMPOSED_LEN" -gt "$max_width" ] && [ "$show_seven_day" -eq 1 ]; then
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

    OUTPUT_TEXT="$COMPOSED_TEXT"
}

render_bars_output() {
    local full_five_time="$five_hour_reset"
    local full_seven_time="$seven_day_reset"
    local short_seven_time="$seven_day_date"
    OUTPUT_TEXT=""

    if [ "$show_bars_git_line" -eq 1 ]; then
        build_bars_git_line
        append_output_line "$LINE_TEXT"
    fi

    if [ "$show_bars_overview_line" -eq 1 ]; then
        build_bars_overview_line
        append_output_line "$LINE_TEXT"
    fi

    if [ "$show_hourly_bar" -eq 1 ]; then
        if [ "$usage_available" -eq 1 ]; then
            build_usage_bar_line "5h" "$five_hour_pct" "${five_hour_pct}%" "$full_five_time" ""
        else
            build_usage_bar_line "5h" 0 "--" "n/a" ""
        fi
        append_output_line "$LINE_TEXT"
    fi

    if [ "$show_daily_bar" -eq 1 ]; then
        if [ "$usage_available" -eq 1 ]; then
            build_usage_bar_line "7d" "$seven_day_pct" "${seven_day_pct}%" "$full_seven_time" "$short_seven_time"
        else
            build_usage_bar_line "7d" 0 "--" "n/a" ""
        fi
        append_output_line "$LINE_TEXT"
    fi
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

is_future_epoch() {
    local iso_str="$1"
    [ -z "$iso_str" ] || [ "$iso_str" = "null" ] && return 1
    local epoch
    epoch=$(iso_to_epoch "$iso_str")
    [ -z "$epoch" ] && return 1
    local now
    now=$(date +%s)
    [ "$epoch" -gt "$now" ]
}

format_reset_time() {
    local iso_str="$1"
    local format_string="$2"
    local trim_hour="$3"
    [ -z "$iso_str" ] || [ "$iso_str" = "null" ] && return

    local epoch
    epoch=$(iso_to_epoch "$iso_str")
    [ -z "$epoch" ] && return

    local formatted=""
    formatted=$(date -d "@$epoch" +"$format_string" 2>/dev/null) || \
    formatted=$(date -j -r "$epoch" +"$format_string" 2>/dev/null)

    if [ -n "$formatted" ] && [ "$trim_hour" = "1" ]; then
        formatted=$(printf "%s" "$formatted" | sed -E 's/(^| )0([0-9]:)/\1\2/g')
    fi

    [ -n "$formatted" ] && printf "%s" "$formatted"
}

seven_day_time_format=$(resolve_seven_day_time_format "$seven_day_time_requested")

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
seven_day_date=""
extra_enabled="false"
extra_used=""
extra_limit=""

if [ -n "$usage_data" ] && echo "$usage_data" | jq -e '.five_hour' >/dev/null 2>&1; then
    usage_available=1
    five_hour_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
    five_hour_reset_iso=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
    if is_future_epoch "$five_hour_reset_iso"; then
        five_hour_reset=$(format_reset_time "$five_hour_reset_iso" "%H:%M" "1")
        [ -n "$five_hour_reset" ] && show_five_hour_reset=1
    fi

    seven_day_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')
    seven_day_reset_iso=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
    if is_future_epoch "$seven_day_reset_iso"; then
        seven_day_reset=$(format_reset_time "$seven_day_reset_iso" "$seven_day_time_format" "0")
        seven_day_date=$(format_reset_time "$seven_day_reset_iso" "$short_seven_day_date_format" "0")
        [ -n "$seven_day_reset" ] && show_seven_day_reset=1
    fi

    extra_enabled=$(echo "$usage_data" | jq -r '.extra_usage.is_enabled // false')
    if [ "$extra_enabled" = "true" ]; then
        extra_used=$(echo "$usage_data" | jq -r '.extra_usage.used_credits // 0' | LC_NUMERIC=C awk '{printf "%.2f", $1/100}')
        extra_limit=$(echo "$usage_data" | jq -r '.extra_usage.monthly_limit // 0' | LC_NUMERIC=C awk '{printf "%.2f", $1/100}')
        show_extra=1
    fi
fi

[ -n "$git_stat" ] && show_git_diff=1
max_width=$(get_max_width)

if [ "$layout_name" = "bars" ]; then
    render_bars_output
else
    render_compact_output 1
fi

printf "%b" "$OUTPUT_TEXT"
exit 0
