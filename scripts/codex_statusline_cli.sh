#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMON_SCRIPT="$SCRIPT_DIR/codex_statusline_common.sh"
STATUS_SCRIPT="$SCRIPT_DIR/codex_statusline.sh"
CONFIG_FILE="${HOME}/.codex/config.toml"

if [ ! -f "$COMMON_SCRIPT" ] || [ ! -f "$STATUS_SCRIPT" ]; then
    printf '缺少 Codex 状态栏依赖脚本\n' >&2
    exit 1
fi

# shellcheck source=./codex_statusline_common.sh
. "$COMMON_SCRIPT"

THEMES=(default forest dracula monokai solarized ocean sunset amber rose)
LAYOUTS=(bars compact)
BAR_STYLES=(ascii dots squares blocks braille shades diamonds)
GIT_DISPLAYS=(repo branch)
SEGMENT_ORDER=(model eff ctx git 5h 7d hook notify buddy)
DEFAULT_SEGMENTS_CSV="model,eff,ctx,git,5h,7d"

trim() {
    printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

ensure_config_file() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    touch "$CONFIG_FILE"
}

read_statusline_value() {
    statusline_toml_get "$CONFIG_FILE" "$1" "$2"
}

upsert_statusline_key() {
    local key="$1"
    local value="$2"
    local tmp_file

    ensure_config_file
    tmp_file=$(mktemp)

    awk -v section="statusline" -v key="$key" -v value="$value" '
        BEGIN {
            in_section = 0
            wrote_key = 0
        }

        $0 ~ "^\\[" section "\\][[:space:]]*$" {
            in_section = 1
            print
            next
        }

        in_section && /^\[/ {
            if (!wrote_key) {
                print key " = " value
                wrote_key = 1
            }
            in_section = 0
        }

        in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            if (!wrote_key) {
                print key " = " value
                wrote_key = 1
            }
            next
        }

        {
            print
        }

        END {
            if (in_section && !wrote_key) {
                print key " = " value
                wrote_key = 1
            }

            if (!wrote_key) {
                if (NR > 0) {
                    print ""
                }
                print "[" section "]"
                print key " = " value
            }
        }
    ' "$CONFIG_FILE" > "$tmp_file"

    mv "$tmp_file" "$CONFIG_FILE"
}

delete_statusline_key() {
    local key="$1"
    local tmp_file

    [ -f "$CONFIG_FILE" ] || return 0

    tmp_file=$(mktemp)
    awk -v section="statusline" -v key="$key" '
        BEGIN {
            in_section = 0
        }

        $0 ~ "^\\[" section "\\][[:space:]]*$" {
            in_section = 1
            print
            next
        }

        in_section && /^\[/ {
            in_section = 0
        }

        in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            next
        }

        {
            print
        }
    ' "$CONFIG_FILE" > "$tmp_file"

    mv "$tmp_file" "$CONFIG_FILE"
}

csv_contains() {
    local csv="$1"
    local needle="$2"
    case ",$csv," in
        *,"$needle",*) return 0 ;;
        *) return 1 ;;
    esac
}

array_contains() {
    local needle="$1"
    shift
    local item

    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done

    return 1
}

normalize_segments_csv() {
    local input_csv="$1"
    local result=()
    local raw segment_name

    for raw in $(printf '%s' "$input_csv" | tr ',' ' '); do
        segment_name=$(trim "$raw")
        case "$segment_name" in
            model|eff|ctx|git|5h|7d|hook|notify|buddy)
                if [ "${#result[@]}" -eq 0 ] || ! array_contains "$segment_name" "${result[@]}"; then
                    result+=("$segment_name")
                fi
                ;;
        esac
    done

    if [ "${#result[@]}" -eq 0 ]; then
        printf '%s' "$DEFAULT_SEGMENTS_CSV"
        return
    fi

    local IFS=,
    printf '%s' "${result[*]}"
}

move_segment() {
    local selected_segment="$1"
    local direction="$2"
    local current_csv="$3"
    local segments=()
    local index target
    local raw

    for raw in $(printf '%s' "$current_csv" | tr ',' ' '); do
        segments+=("$raw")
    done

    for index in "${!segments[@]}"; do
        [ "${segments[$index]}" = "$selected_segment" ] || continue
        if [ "$direction" = "left" ] && [ "$index" -gt 0 ]; then
            target=$(( index - 1 ))
        elif [ "$direction" = "right" ] && [ "$index" -lt $(( ${#segments[@]} - 1 )) ]; then
            target=$(( index + 1 ))
        else
            break
        fi
        raw="${segments[$target]}"
        segments[$target]="${segments[$index]}"
        segments[$index]="$raw"
        break
    done

    local IFS=,
    printf '%s' "${segments[*]}"
}

next_list_value() {
    local current="$1"
    shift
    local values=("$@")
    local index

    for index in "${!values[@]}"; do
        if [ "${values[$index]}" = "$current" ]; then
            printf '%s' "${values[$(( (index + 1) % ${#values[@]} ))]}"
            return
        fi
    done

    printf '%s' "${values[0]}"
}

previous_list_value() {
    local current="$1"
    shift
    local values=("$@")
    local index

    for index in "${!values[@]}"; do
        if [ "${values[$index]}" = "$current" ]; then
            if [ "$index" -eq 0 ]; then
                printf '%s' "${values[$(( ${#values[@]} - 1 ))]}"
            else
                printf '%s' "${values[$(( index - 1 ))]}"
            fi
            return
        fi
    done

    printf '%s' "${values[0]}"
}

value_in_list() {
    local needle="$1"
    shift
    array_contains "$needle" "$@"
}

load_state() {
    theme_value=$(read_statusline_value "theme" "default")
    layout_value=$(read_statusline_value "layout" "bars")
    bar_style_value=$(read_statusline_value "bar_style" "ascii")
    git_display_value=$(read_statusline_value "git_display" "repo")
    value_in_list "$git_display_value" "${GIT_DISPLAYS[@]}" || git_display_value="repo"
    segments_value=$(normalize_segments_csv "$(read_statusline_value "segments" "$DEFAULT_SEGMENTS_CSV")")
    show_git_line_value=$(statusline_resolve_bool_setting "$(read_statusline_value "show_git_line" "")" "1")
    show_overview_line_value=$(statusline_resolve_bool_setting "$(read_statusline_value "show_overview_line" "")" "1")
    show_hook_segment_value=$(statusline_resolve_bool_setting "$(read_statusline_value "show_hook_segment" "")" "0")
    show_notify_segment_value=$(statusline_resolve_bool_setting "$(read_statusline_value "show_notify_segment" "")" "0")
    show_buddy_segment_value=$(statusline_resolve_bool_setting "$(read_statusline_value "show_buddy_segment" "")" "0")
}

persist_state() {
    if [ "$theme_value" = "default" ]; then
        delete_statusline_key "theme"
    else
        upsert_statusline_key "theme" "\"$theme_value\""
    fi

    if [ "$layout_value" = "bars" ]; then
        delete_statusline_key "layout"
    else
        upsert_statusline_key "layout" "\"$layout_value\""
    fi

    if [ "$bar_style_value" = "ascii" ]; then
        delete_statusline_key "bar_style"
    else
        upsert_statusline_key "bar_style" "\"$bar_style_value\""
    fi

    if [ "$git_display_value" = "repo" ]; then
        delete_statusline_key "git_display"
    else
        upsert_statusline_key "git_display" "\"$git_display_value\""
    fi

    if [ "$segments_value" = "$DEFAULT_SEGMENTS_CSV" ]; then
        delete_statusline_key "segments"
    else
        upsert_statusline_key "segments" "\"$segments_value\""
    fi

    if [ "$show_git_line_value" = "1" ]; then
        delete_statusline_key "show_git_line"
    else
        upsert_statusline_key "show_git_line" "false"
    fi

    if [ "$show_overview_line_value" = "1" ]; then
        delete_statusline_key "show_overview_line"
    else
        upsert_statusline_key "show_overview_line" "false"
    fi

    if [ "$show_hook_segment_value" = "0" ]; then
        delete_statusline_key "show_hook_segment"
    else
        upsert_statusline_key "show_hook_segment" "true"
    fi

    if [ "$show_notify_segment_value" = "0" ]; then
        delete_statusline_key "show_notify_segment"
    else
        upsert_statusline_key "show_notify_segment" "true"
    fi

    if [ "$show_buddy_segment_value" = "0" ]; then
        delete_statusline_key "show_buddy_segment"
    else
        upsert_statusline_key "show_buddy_segment" "true"
    fi
}

print_state_table() {
    load_state
    cat <<EOF
当前 Codex 状态栏配置：

- theme: $theme_value
- layout: $layout_value
- bar_style: $bar_style_value
- git_display: $git_display_value
- segments: $segments_value
- show_git_line: $( [ "$show_git_line_value" = "1" ] && printf 'true' || printf 'false' )
- show_overview_line: $( [ "$show_overview_line_value" = "1" ] && printf 'true' || printf 'false' )
- show_hook_segment: $( [ "$show_hook_segment_value" = "1" ] && printf 'true' || printf 'false' )
- show_notify_segment: $( [ "$show_notify_segment_value" = "1" ] && printf 'true' || printf 'false' )
- show_buddy_segment: $( [ "$show_buddy_segment_value" = "1" ] && printf 'true' || printf 'false' )

命令：
- ./scripts/codex_statusline_cli.sh preview
- ./scripts/codex_statusline_cli.sh configure
- ./scripts/codex_statusline_cli.sh theme dracula
EOF
}

build_preview() {
    local preview_dir="${1:-$PWD}"
    local temp_dir session_file hook_cache notify_cache buddy_cache now_epoch

    temp_dir=$(mktemp -d)
    session_file="$temp_dir/preview.jsonl"
    hook_cache="$temp_dir/hook.json"
    notify_cache="$temp_dir/notify.json"
    buddy_cache="$temp_dir/buddy.json"
    now_epoch=$(date +%s)

    cat > "$session_file" <<EOF
{"timestamp":"2026-03-13T03:19:14.442Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":8523974,"cached_input_tokens":7543552,"output_tokens":23658,"reasoning_output_tokens":5371,"total_tokens":8547632},"last_token_usage":{"input_tokens":128588,"cached_input_tokens":5504,"output_tokens":728,"reasoning_output_tokens":185,"total_tokens":129316},"model_context_window":258400},"rate_limits":{"primary":{"used_percent":3.0,"window_minutes":300,"resets_at":4102444800},"secondary":{"used_percent":15.0,"window_minutes":10080,"resets_at":4103049600},"credits":{"has_credits":false,"unlimited":false,"balance":null},"plan_type":null}}}
EOF

    printf '{"updated_at":%s,"summary":"bash ok"}\n' "$now_epoch" > "$hook_cache"
    printf '{"updated_at":%s,"summary":"Waiting for approval"}\n' "$now_epoch" > "$notify_cache"
    printf '{"updated_at":%s,"status":"needs_input","summary":"review migration"}\n' "$now_epoch" > "$buddy_cache"

    CODEX_STATUSLINE_FORMAT=ansi \
    CODEX_STATUSLINE_SESSION_FILE="$session_file" \
    CODEX_STATUSLINE_CACHE_FILE="$temp_dir/session-cache.json" \
    CODEX_STATUSLINE_MAX_WIDTH="${CODEX_STATUSLINE_PREVIEW_WIDTH:-100}" \
    CODEX_STATUSLINE_THEME="$theme_value" \
    CODEX_STATUSLINE_LAYOUT="$layout_value" \
    CODEX_STATUSLINE_BAR_STYLE="$bar_style_value" \
    CODEX_STATUSLINE_GIT_DISPLAY="$git_display_value" \
    CODEX_STATUSLINE_SEGMENTS="$segments_value" \
    CODEX_STATUSLINE_SHOW_GIT_LINE="$show_git_line_value" \
    CODEX_STATUSLINE_SHOW_OVERVIEW_LINE="$show_overview_line_value" \
    CODEX_STATUSLINE_SHOW_HOOK_SEGMENT="$show_hook_segment_value" \
    CODEX_STATUSLINE_SHOW_NOTIFY_SEGMENT="$show_notify_segment_value" \
    CODEX_STATUSLINE_SHOW_BUDDY_SEGMENT="$show_buddy_segment_value" \
    CODEX_STATUSLINE_HOOK_CACHE_FILE="$hook_cache" \
    CODEX_STATUSLINE_NOTIFY_CACHE_FILE="$notify_cache" \
    CODEX_STATUSLINE_BUDDY_CACHE_FILE="$buddy_cache" \
    /bin/bash "$STATUS_SCRIPT" "$preview_dir"

    rm -rf "$temp_dir"
}

print_help() {
    cat <<'EOF'
用法：
  ./scripts/codex_statusline_cli.sh show
  ./scripts/codex_statusline_cli.sh preview
  ./scripts/codex_statusline_cli.sh configure
  ./scripts/codex_statusline_cli.sh theme <name>
  ./scripts/codex_statusline_cli.sh layout <bars|compact>
  ./scripts/codex_statusline_cli.sh bar-style <name>
  ./scripts/codex_statusline_cli.sh git-display <repo|branch>
EOF
}

set_single_value() {
    local key="$1"
    local value="$2"

    case "$key" in
        theme)
            value_in_list "$value" "${THEMES[@]}" || {
                printf '无效 theme: %s\n' "$value" >&2
                exit 1
            }
            theme_value="$value"
            ;;
        layout)
            value_in_list "$value" "${LAYOUTS[@]}" || {
                printf '无效 layout: %s\n' "$value" >&2
                exit 1
            }
            layout_value="$value"
            ;;
        bar-style)
            value_in_list "$value" "${BAR_STYLES[@]}" || {
                printf '无效 bar-style: %s\n' "$value" >&2
                exit 1
            }
            bar_style_value="$value"
            ;;
        git-display)
            value_in_list "$value" "${GIT_DISPLAYS[@]}" || {
                printf '无效 git-display: %s\n' "$value" >&2
                exit 1
            }
            git_display_value="$value"
            ;;
        *)
            printf '未知配置项: %s\n' "$key" >&2
            exit 1
            ;;
    esac

    persist_state
    printf '✅ %s 已更新为 %s\n' "$key" "$value"
}

reset_state() {
    theme_value="default"
    layout_value="bars"
    bar_style_value="ascii"
    git_display_value="repo"
    segments_value="$DEFAULT_SEGMENTS_CSV"
    show_git_line_value="1"
    show_overview_line_value="1"
    show_hook_segment_value="0"
    show_notify_segment_value="0"
    show_buddy_segment_value="0"
}

segment_enabled_in_state() {
    csv_contains "$segments_value" "$1"
}

toggle_segment() {
    local segment_name="$1"
    local result=()
    local raw

    if segment_enabled_in_state "$segment_name"; then
        for raw in $(printf '%s' "$segments_value" | tr ',' ' '); do
            [ "$raw" = "$segment_name" ] && continue
            result+=("$raw")
        done
    else
        result=()
        for raw in $(printf '%s' "$segments_value" | tr ',' ' '); do
            result+=("$raw")
        done
        result+=("$segment_name")
    fi

    if [ "${#result[@]}" -eq 0 ]; then
        result=(model)
    fi

    local IFS=,
    segments_value="${result[*]}"
}

toggle_boolean() {
    local value="$1"
    if [ "$value" = "1" ]; then
        printf '0'
    else
        printf '1'
    fi
}

build_segment_rows() {
    local raw
    SEGMENT_ROWS=()

    for raw in $(printf '%s' "$segments_value" | tr ',' ' '); do
        SEGMENT_ROWS+=("$raw")
    done

    for raw in "${SEGMENT_ORDER[@]}"; do
        if [ "${#SEGMENT_ROWS[@]}" -eq 0 ] || ! array_contains "$raw" "${SEGMENT_ROWS[@]}"; then
            SEGMENT_ROWS+=("$raw")
        fi
    done
}

build_menu_rows() {
    MENU_ROWS=(
        "theme"
        "layout"
        "bar_style"
        "git_display"
        "show_git_line"
        "show_overview_line"
        "show_hook_segment"
        "show_notify_segment"
        "show_buddy_segment"
    )

    build_segment_rows

    local segment_name
    for segment_name in "${SEGMENT_ROWS[@]}"; do
        MENU_ROWS+=("segment:$segment_name")
    done

    MENU_ROWS+=(
        "action:save"
        "action:reset"
        "action:quit"
    )
}

read_key() {
    local key rest
    IFS= read -rsn1 key || return 1
    if [ "$key" = $'\033' ]; then
        if IFS= read -rsn1 rest; then
            key+="$rest"
        fi
        if [ "${key#"$'\033'"}" = "[" ] && IFS= read -rsn1 rest; then
            key+="$rest"
        fi
    fi
    printf '%s' "$key"
}

render_configure_screen() {
    local selected_index="$1"
    local index row cursor title checked

    build_menu_rows

    printf '\033[H\033[J'
    printf 'Configure Codex Statusline\n\n'
    printf '重度命令行用户模式：改配置时直接看预览，不再来回改 config.toml。\n'
    printf '按键：↑/↓ 选择  Enter/Space 切换  ←/→ 调整或重排  s 保存  r 重置  q 退出\n\n'

    for index in "${!MENU_ROWS[@]}"; do
        row="${MENU_ROWS[$index]}"
        cursor=" "
        [ "$index" -eq "$selected_index" ] && cursor=">"

        case "$row" in
            theme)
                printf '%s  theme            %s\n' "$cursor" "$theme_value"
                ;;
            layout)
                printf '%s  layout           %s\n' "$cursor" "$layout_value"
                ;;
            bar_style)
                printf '%s  bar-style        %s\n' "$cursor" "$bar_style_value"
                ;;
            git_display)
                printf '%s  git-display      %s\n' "$cursor" "$git_display_value"
                ;;
            show_git_line)
                checked="[ ]"
                [ "$show_git_line_value" = "1" ] && checked="[x]"
                printf '%s  %s show git line\n' "$cursor" "$checked"
                ;;
            show_overview_line)
                checked="[ ]"
                [ "$show_overview_line_value" = "1" ] && checked="[x]"
                printf '%s  %s show overview line\n' "$cursor" "$checked"
                ;;
            show_hook_segment)
                checked="[ ]"
                [ "$show_hook_segment_value" = "1" ] && checked="[x]"
                printf '%s  %s hook segment\n' "$cursor" "$checked"
                ;;
            show_notify_segment)
                checked="[ ]"
                [ "$show_notify_segment_value" = "1" ] && checked="[x]"
                printf '%s  %s notify segment\n' "$cursor" "$checked"
                ;;
            show_buddy_segment)
                checked="[ ]"
                [ "$show_buddy_segment_value" = "1" ] && checked="[x]"
                printf '%s  %s buddy segment\n' "$cursor" "$checked"
                ;;
            segment:*)
                title="${row#segment:}"
                checked="[ ]"
                segment_enabled_in_state "$title" && checked="[x]"
                printf '%s  %s %s\n' "$cursor" "$checked" "$title"
                ;;
            action:save)
                printf '%s  保存配置\n' "$cursor"
                ;;
            action:reset)
                printf '%s  恢复默认\n' "$cursor"
                ;;
            action:quit)
                printf '%s  退出不保存\n' "$cursor"
                ;;
        esac
    done

    printf '\nPreview:\n'
    build_preview "$PWD"
    printf '\n'
}

run_configure() {
    local selected_index=0
    local rows_count key selected_row segment_name

    load_state
    trap 'printf "\033[?25h"' EXIT
    printf '\033[?25l'

    while true; do
        build_menu_rows
        rows_count=${#MENU_ROWS[@]}
        render_configure_screen "$selected_index"
        key=$(read_key) || {
            printf '\n已取消，配置未保存\n'
            return 0
        }
        selected_row="${MENU_ROWS[$selected_index]}"

        case "$key" in
            $'\033[A')
                if [ "$selected_index" -gt 0 ]; then
                    selected_index=$(( selected_index - 1 ))
                fi
                ;;
            $'\033[B')
                if [ "$selected_index" -lt $(( rows_count - 1 )) ]; then
                    selected_index=$(( selected_index + 1 ))
                fi
                ;;
            $'\033[C'|"l")
                case "$selected_row" in
                    theme) theme_value=$(next_list_value "$theme_value" "${THEMES[@]}") ;;
                    layout) layout_value=$(next_list_value "$layout_value" "${LAYOUTS[@]}") ;;
                    bar_style) bar_style_value=$(next_list_value "$bar_style_value" "${BAR_STYLES[@]}") ;;
                    git_display) git_display_value=$(next_list_value "$git_display_value" "${GIT_DISPLAYS[@]}") ;;
                    segment:*)
                        segment_name="${selected_row#segment:}"
                        segments_value=$(move_segment "$segment_name" right "$segments_value")
                        build_menu_rows
                        ;;
                esac
                ;;
            $'\033[D'|"h")
                case "$selected_row" in
                    theme) theme_value=$(previous_list_value "$theme_value" "${THEMES[@]}") ;;
                    layout) layout_value=$(previous_list_value "$layout_value" "${LAYOUTS[@]}") ;;
                    bar_style) bar_style_value=$(previous_list_value "$bar_style_value" "${BAR_STYLES[@]}") ;;
                    git_display) git_display_value=$(previous_list_value "$git_display_value" "${GIT_DISPLAYS[@]}") ;;
                    segment:*)
                        segment_name="${selected_row#segment:}"
                        segments_value=$(move_segment "$segment_name" left "$segments_value")
                        build_menu_rows
                        ;;
                esac
                ;;
            ""|" "|$'\n')
                case "$selected_row" in
                    theme) theme_value=$(next_list_value "$theme_value" "${THEMES[@]}") ;;
                    layout) layout_value=$(next_list_value "$layout_value" "${LAYOUTS[@]}") ;;
                    bar_style) bar_style_value=$(next_list_value "$bar_style_value" "${BAR_STYLES[@]}") ;;
                    git_display) git_display_value=$(next_list_value "$git_display_value" "${GIT_DISPLAYS[@]}") ;;
                    show_git_line) show_git_line_value=$(toggle_boolean "$show_git_line_value") ;;
                    show_overview_line) show_overview_line_value=$(toggle_boolean "$show_overview_line_value") ;;
                    show_hook_segment) show_hook_segment_value=$(toggle_boolean "$show_hook_segment_value") ;;
                    show_notify_segment) show_notify_segment_value=$(toggle_boolean "$show_notify_segment_value") ;;
                    show_buddy_segment) show_buddy_segment_value=$(toggle_boolean "$show_buddy_segment_value") ;;
                    segment:*)
                        segment_name="${selected_row#segment:}"
                        toggle_segment "$segment_name"
                        build_menu_rows
                        ;;
                    action:save)
                        persist_state
                        printf '\033[H\033[J✅ Codex 状态栏配置已保存\n'
                        return 0
                        ;;
                    action:reset)
                        reset_state
                        ;;
                    action:quit)
                        printf '\033[H\033[J已退出，未保存变更\n'
                        return 0
                        ;;
                esac
                ;;
            s|S)
                persist_state
                printf '\033[H\033[J✅ Codex 状态栏配置已保存\n'
                return 0
                ;;
            r|R)
                reset_state
                ;;
            q|Q)
                printf '\033[H\033[J已退出，未保存变更\n'
                return 0
                ;;
        esac
    done
}

command="${1:-show}"
case "$command" in
    show)
        print_state_table
        ;;
    preview)
        load_state
        build_preview "$PWD"
        ;;
    configure)
        run_configure
        ;;
    theme|layout|bar-style|git-display)
        [ -n "${2:-}" ] || {
            print_help >&2
            exit 1
        }
        load_state
        set_single_value "$command" "$2"
        ;;
    -h|--help|help)
        print_help
        ;;
    *)
        print_help >&2
        exit 1
        ;;
esac
