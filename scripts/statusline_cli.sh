#!/usr/bin/env bash

set -euo pipefail

THEMES="default forest dracula monokai solarized ocean sunset amber rose"
SETTINGS_FILE="${HOME}/.claude/settings.json"

print_help() {
    cat <<'EOF'
用法:
  ./scripts/statusline_cli.sh show
  ./scripts/statusline_cli.sh preview [theme]
  ./scripts/statusline_cli.sh theme [theme]

说明:
  show            显示当前 Claude 状态栏主题
  preview [theme] 预览指定主题；未指定则预览当前主题
  theme [theme]   直接切换主题；不带参数时进入交互式预览模式
EOF
}

theme_description() {
    case "$1" in
        default) printf "蓝青主调，暗色终端高对比" ;;
        forest) printf "绿色主调，柔和自然" ;;
        dracula) printf "紫色主调，暗色背景下表现出色" ;;
        monokai) printf "青色主调，经典代码编辑器风格" ;;
        solarized) printf "蓝色主调，低对比度护眼" ;;
        ocean) printf "青蓝主调，清爽海洋风" ;;
        sunset) printf "珊瑚橙主调，温暖日落氛围" ;;
        amber) printf "琥珀金主调，沉稳大地色" ;;
        rose) printf "玫瑰粉主调，柔和优雅" ;;
        *) return 1 ;;
    esac
}

theme_palette() {
    case "$1" in
        forest) printf '%s' '120;196;120|94;170;150|214;224;205|138;150;130|224;108;117|214;170;84|198;183;101|120;196;120|234;238;228' ;;
        dracula) printf '%s' '189;147;249|139;233;253|248;248;242|132;145;182|255;85;85|255;184;108|241;250;140|80;250;123|248;248;242' ;;
        monokai) printf '%s' '102;217;239|166;226;46|230;219;116|153;147;101|249;38;114|253;151;31|230;219;116|166;226;46|248;248;242' ;;
        solarized) printf '%s' '38;139;210|42;161;152|147;161;161|133;149;150|220;50;47|203;75;22|181;137;0|133;153;0|238;232;213' ;;
        ocean) printf '%s' '0;188;212|0;151;167|178;235;242|124;150;162|239;83;80|255;152;0|255;213;79|102;187;106|224;247;250' ;;
        sunset) printf '%s' '255;138;101|255;183;77|255;204;128|167;140;127|239;83;80|255;112;66|255;213;79|174;213;129|255;243;224' ;;
        amber) printf '%s' '255;193;7|220;184;106|240;230;200|158;148;119|232;98;92|232;152;62|212;170;50|140;179;105|245;240;224' ;;
        rose) printf '%s' '244;143;177|206;147;216|248;215;224|173;139;159|239;83;80|255;138;101|255;213;79|165;214;167|253;232;239' ;;
        *) printf '%s' '96;165;250|45;212;191|226;232;240|148;163;184|248;113;113|251;146;60|251;191;36|52;211;153|229;231;235' ;;
    esac
}

normalize_input() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'
}

ensure_settings_file() {
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    if [ ! -f "$SETTINGS_FILE" ]; then
        printf '%s\n' '{"env":{}}' > "$SETTINGS_FILE"
    fi
}

current_theme() {
    ensure_settings_file
    jq -r '.env.CLAUDE_CODE_STATUSLINE_THEME // "default"' "$SETTINGS_FILE" 2>/dev/null || printf 'default'
}

write_theme_setting() {
    local theme="$1"
    local tmp_file

    ensure_settings_file
    tmp_file=$(mktemp)
    jq --arg val "$theme" '.env //= {} | .env.CLAUDE_CODE_STATUSLINE_THEME = $val' "$SETTINGS_FILE" > "$tmp_file"
    mv "$tmp_file" "$SETTINGS_FILE"
}

resolve_theme() {
    local query normalized exact_match prefix_matches contains_matches theme

    normalized=$(normalize_input "$1")
    [ -n "$normalized" ] || return 1

    exact_match=""
    prefix_matches=""
    contains_matches=""

    for theme in $THEMES; do
        if [ "$theme" = "$normalized" ]; then
            exact_match="$theme"
            break
        fi
        case "$theme" in
            "$normalized"*) prefix_matches="${prefix_matches}${theme}"$'\n' ;;
            *"$normalized"*) contains_matches="${contains_matches}${theme}"$'\n' ;;
        esac
    done

    if [ -n "$exact_match" ]; then
        printf '%s' "$exact_match"
        return 0
    fi

    if [ -n "$prefix_matches" ]; then
        if [ "$(printf '%s' "$prefix_matches" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ]; then
            printf '%s' "$prefix_matches" | sed -n '/./{p;q;}'
            return 0
        fi
        printf '匹配到多个主题:\n%s' "$(printf '%s' "$prefix_matches" | sed '/^$/d' | sed 's/^/- /')" >&2
        return 1
    fi

    if [ -n "$contains_matches" ]; then
        if [ "$(printf '%s' "$contains_matches" | sed '/^$/d' | wc -l | tr -d ' ')" = "1" ]; then
            printf '%s' "$contains_matches" | sed -n '/./{p;q;}'
            return 0
        fi
        printf '匹配到多个主题:\n%s' "$(printf '%s' "$contains_matches" | sed '/^$/d' | sed 's/^/- /')" >&2
        return 1
    fi

    printf '未知主题: %s\n' "$1" >&2
    return 1
}

print_theme_menu() {
    local candidate="$1" theme marker

    printf '可用主题：\n\n'
    for theme in $THEMES; do
        if [ "$theme" = "$candidate" ]; then
            marker="(●)"
        else
            marker="( )"
        fi
        printf '%s %-10s %s\n' "$marker" "$theme" "$(theme_description "$theme")"
    done
}

print_color_swatch() {
    local rgb="$1"
    local label="$2"
    printf '\033[48;2;%sm  \033[0m %s  ' "$rgb" "$label"
}

preview_theme() {
    local theme="$1"
    local palette accent teal branch muted red orange yellow green white
    local old_ifs="$IFS"

    palette=$(theme_palette "$theme")
    IFS='|' read -r accent teal branch muted red orange yellow green white <<EOF
$palette
EOF
    IFS="$old_ifs"

    printf '%s 主题色板：\n' "$theme"
    print_color_swatch "$accent" "accent"
    print_color_swatch "$teal" "teal"
    print_color_swatch "$branch" "branch"
    printf '\n'
    print_color_swatch "$muted" "muted"
    print_color_swatch "$red" "red"
    print_color_swatch "$orange" "orange"
    printf '\n'
    print_color_swatch "$yellow" "yellow"
    print_color_swatch "$green" "green"
    print_color_swatch "$white" "white"
    printf '\n'
}

show_current_theme() {
    local theme
    theme=$(current_theme)
    printf '当前主题：%s\n' "$theme"
}

set_theme_direct() {
    local requested="$1" resolved previous
    resolved=$(resolve_theme "$requested")
    previous=$(current_theme)
    write_theme_setting "$resolved"
    printf '✅ theme: %s → %s\n' "$previous" "$resolved"
}

interactive_theme() {
    local original_theme candidate_theme user_input resolved_theme

    original_theme=$(current_theme)
    candidate_theme="$original_theme"

    while true; do
        print_theme_menu "$candidate_theme"
        printf '\n当前主题：%s\n' "$original_theme"
        printf '当前预览：%s\n' "$candidate_theme"
        preview_theme "$candidate_theme"
        printf '提示：这是模拟预览，尚未写入真实 footer。\n'
        printf '输入主题名继续预览，或输入 confirm / cancel: '

        if ! IFS= read -r user_input; then
            printf '\n已取消，保持 %s\n' "$original_theme"
            return 0
        fi

        user_input=$(printf '%s' "$user_input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        case "$(normalize_input "$user_input")" in
            confirm)
                if [ "$candidate_theme" = "$original_theme" ]; then
                    printf '未修改主题，保持 %s\n' "$original_theme"
                else
                    write_theme_setting "$candidate_theme"
                    printf '✅ theme: %s → %s\n' "$original_theme" "$candidate_theme"
                fi
                return 0
                ;;
            cancel)
                printf '已取消，保持 %s\n' "$original_theme"
                return 0
                ;;
            "")
                printf '\n'
                ;;
            *)
                if resolved_theme=$(resolve_theme "$user_input" 2>/dev/null); then
                    candidate_theme="$resolved_theme"
                    printf '\n'
                else
                    printf '无效主题输入，请重试。\n\n'
                fi
                ;;
        esac
    done
}

command="${1:-show}"
case "$command" in
    show)
        show_current_theme
        ;;
    preview)
        if [ "${2:-}" != "" ]; then
            preview_theme "$(resolve_theme "$2")"
        else
            preview_theme "$(current_theme)"
        fi
        ;;
    theme)
        if [ "${2:-}" != "" ]; then
            set_theme_direct "$2"
        else
            interactive_theme
        fi
        ;;
    -h|--help|help)
        print_help
        ;;
    *)
        print_help >&2
        exit 1
        ;;
esac
