#!/bin/bash
#
# StatusLine 配置管理脚本
# 用于管理 Claude Code 状态栏配置
#

set -e

SETTINGS_FILE="$HOME/.claude/settings.json"

# 默认值
DEFAULT_THEME="default"
DEFAULT_LAYOUT="bars"
DEFAULT_BAR_STYLE="ascii"
DEFAULT_MAX_WIDTH="750"

# 可选值
THEMES="default forest dracula monokai solarized ocean sunset amber rose"
LAYOUTS="compact bars"
BAR_STYLES="ascii dots squares blocks braille shades diamonds"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# 打印帮助
print_help() {
    echo -e "${BOLD}StatusLine 配置管理${RESET}"
    echo ""
    echo -e "${CYAN}用法:${RESET}"
    echo "  /statusline                  显示当前配置 + 帮助"
    echo "  /statusline show             显示当前配置表格"
    echo "  /statusline theme [值]       切换主题"
    echo "  /statusline layout [值]      切换布局"
    echo "  /statusline bar-style [值]   切换进度条样式"
    echo "  /statusline max-width [值]   设置最大宽度"
    echo "  /statusline reset            恢复默认配置"
    echo ""
    echo -e "${CYAN}默认配置:${RESET}"
    echo -e "  theme: ${DIM}$DEFAULT_THEME${RESET}, layout: ${DIM}$DEFAULT_LAYOUT${RESET}, max-width: ${DIM}$DEFAULT_MAX_WIDTH${RESET}"
    echo ""
    echo -e "${CYAN}可用主题:${RESET} $THEMES"
    echo -e "${CYAN}可用布局:${RESET} $LAYOUTS"
    echo -e "${CYAN}进度条样式:${RESET} $BAR_STYLES"
    echo ""
    echo -e "${DIM}配置文件: $SETTINGS_FILE${RESET}"
}

# 确保 settings.json 存在
ensure_settings_file() {
    if [ ! -f "$SETTINGS_FILE" ]; then
        echo -e "${YELLOW}⚠ 配置文件不存在，正在创建...${RESET}"
        mkdir -p "$(dirname "$SETTINGS_FILE")"
        echo '{"env":{}}' > "$SETTINGS_FILE"
    fi
}

# 读取配置值
get_config() {
    local key="$1"
    local default="$2"
    
    if [ -f "$SETTINGS_FILE" ]; then
        local value
        value=$(jq -r ".env.$key // empty" "$SETTINGS_FILE" 2>/dev/null)
        if [ -n "$value" ] && [ "$value" != "null" ]; then
            echo "$value"
            return
        fi
    fi
    echo "$default"
}

# 设置配置值
set_config() {
    local key="$1"
    local value="$2"
    
    ensure_settings_file
    
    # 读取现有内容
    local content
    content=$(cat "$SETTINGS_FILE")
    
    # 更新 env 中的值
    local updated
    updated=$(echo "$content" | jq --arg k "$key" --arg v "$value" '
        .env[$k] = $v
    ')
    
    echo "$updated" > "$SETTINGS_FILE"
}

# 删除配置值
delete_config() {
    local key="$1"
    
    if [ -f "$SETTINGS_FILE" ]; then
        local content
        content=$(cat "$SETTINGS_FILE")
        local updated
        updated=$(echo "$content" | jq --arg k "$key" 'del(.env[$k])')
        echo "$updated" > "$SETTINGS_FILE"
    fi
}

# 打印配置表格
print_config_table() {
    local theme layout bar_style max_width
    
    theme=$(get_config "CLAUDE_CODE_STATUSLINE_THEME" "$DEFAULT_THEME")
    layout=$(get_config "CLAUDE_CODE_STATUSLINE_LAYOUT" "$DEFAULT_LAYOUT")
    bar_style=$(get_config "CLAUDE_CODE_STATUSLINE_BAR_STYLE" "$DEFAULT_BAR_STYLE")
    max_width=$(get_config "CLAUDE_CODE_STATUSLINE_MAX_WIDTH" "$DEFAULT_MAX_WIDTH")
    
    echo ""
    echo -e "${BOLD}┌─────────────────┬──────────────┐${RESET}"
    echo -e "${BOLD}│${RESET} 配置项          ${BOLD}│${RESET} 当前值      ${BOLD}│${RESET}"
    echo -e "${BOLD}├─────────────────┼──────────────┤${RESET}"
    printf "${BOLD}│${RESET} %-15s ${BOLD}│${RESET} %-12s ${BOLD}│${RESET}\n" "theme" "$theme"
    printf "${BOLD}│${RESET} %-15s ${BOLD}│${RESET} %-12s ${BOLD}│${RESET}\n" "layout" "$layout"
    printf "${BOLD}│${RESET} %-15s ${BOLD}│${RESET} %-12s ${BOLD}│${RESET}\n" "bar-style" "$bar_style"
    printf "${BOLD}│${RESET} %-15s ${BOLD}│${RESET} %-12s ${BOLD}│${RESET}\n" "max-width" "$max_width"
    echo -e "${BOLD}└─────────────────┴──────────────┘${RESET}"
    echo ""
}

# 验证主题
validate_theme() {
    local value="$1"
    for t in $THEMES; do
        if [ "$t" = "$value" ]; then
            return 0
        fi
    done
    return 1
}

# 验证布局
validate_layout() {
    local value="$1"
    for l in $LAYOUTS; do
        if [ "$l" = "$value" ]; then
            return 0
        fi
    done
    return 1
}

# 验证进度条样式
validate_bar_style() {
    local value="$1"
    # 检查标准样式
    for s in $BAR_STYLES; do
        if [ "$s" = "$value" ]; then
            return 0
        fi
    done
    # 检查自定义格式 custom:X:Y
    if [[ "$value" =~ ^custom:.+:.+$ ]]; then
        return 0
    fi
    return 1
}

# 设置主题
set_theme() {
    local value="$1"
    local old_value
    old_value=$(get_config "CLAUDE_CODE_STATUSLINE_THEME" "$DEFAULT_THEME")
    
    if validate_theme "$value"; then
        set_config "CLAUDE_CODE_STATUSLINE_THEME" "$value"
        echo -e "${GREEN}✓${RESET} theme: ${DIM}$old_value${RESET} → ${BOLD}$value${RESET}"
    else
        echo -e "${RED}✗ 无效的主题: $value${RESET}"
        echo -e "${DIM}可用主题: $THEMES${RESET}"
        return 1
    fi
}

# 设置布局
set_layout() {
    local value="$1"
    local old_value
    old_value=$(get_config "CLAUDE_CODE_STATUSLINE_LAYOUT" "$DEFAULT_LAYOUT")
    
    if validate_layout "$value"; then
        set_config "CLAUDE_CODE_STATUSLINE_LAYOUT" "$value"
        echo -e "${GREEN}✓${RESET} layout: ${DIM}$old_value${RESET} → ${BOLD}$value${RESET}"
        
        # 提示 bar-style 在 bars 布局下更有效
        if [ "$value" = "bars" ]; then
            local current_style
            current_style=$(get_config "CLAUDE_CODE_STATUSLINE_BAR_STYLE" "$DEFAULT_BAR_STYLE")
            if [ "$current_style" = "ascii" ]; then
                echo -e "${YELLOW}提示: 使用 bars 布局时，建议设置非 ascii 的 bar-style${RESET}"
            fi
        fi
    else
        echo -e "${RED}✗ 无效的布局: $value${RESET}"
        echo -e "${DIM}可用布局: $LAYOUTS${RESET}"
        return 1
    fi
}

# 设置进度条样式
set_bar_style() {
    local value="$1"
    local old_value
    old_value=$(get_config "CLAUDE_CODE_STATUSLINE_BAR_STYLE" "$DEFAULT_BAR_STYLE")
    
    if validate_bar_style "$value"; then
        set_config "CLAUDE_CODE_STATUSLINE_BAR_STYLE" "$value"
        echo -e "${GREEN}✓${RESET} bar-style: ${DIM}$old_value${RESET} → ${BOLD}$value${RESET}"
        
        # 提示需要 bars 布局
        local current_layout
        current_layout=$(get_config "CLAUDE_CODE_STATUSLINE_LAYOUT" "$DEFAULT_LAYOUT")
        if [ "$current_layout" != "bars" ]; then
            echo -e "${YELLOW}提示: bar-style 仅在 layout=bars 时生效${RESET}"
        fi
    else
        echo -e "${RED}✗ 无效的进度条样式: $value${RESET}"
        echo -e "${DIM}可用样式: $BAR_STYLES 或 custom:填充:空白${RESET}"
        return 1
    fi
}

# 验证最大宽度
validate_max_width() {
    local value="$1"
    # 必须是正整数或 auto
    if [ "$value" = "auto" ]; then
        return 0
    fi
    if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
        return 0
    fi
    return 1
}

# 设置最大宽度
set_max_width() {
    local value="$1"
    local old_value
    old_value=$(get_config "CLAUDE_CODE_STATUSLINE_MAX_WIDTH" "$DEFAULT_MAX_WIDTH")
    
    if validate_max_width "$value"; then
        set_config "CLAUDE_CODE_STATUSLINE_MAX_WIDTH" "$value"
        echo -e "${GREEN}✓${RESET} max-width: ${DIM}$old_value${RESET} → ${BOLD}$value${RESET}"
    else
        echo -e "${RED}✗ 无效的最大宽度: $value${RESET}"
        echo -e "${DIM}应为正整数或 auto${RESET}"
        return 1
    fi
}

# 重置配置
reset_config() {
    delete_config "CLAUDE_CODE_STATUSLINE_THEME"
    delete_config "CLAUDE_CODE_STATUSLINE_LAYOUT"
    delete_config "CLAUDE_CODE_STATUSLINE_BAR_STYLE"
    delete_config "CLAUDE_CODE_STATUSLINE_MAX_WIDTH"
    echo -e "${GREEN}✓ 已恢复默认配置${RESET}"
    print_config_table
}

# 主逻辑
main() {
    local command="${1:-}"
    local value="${2:-}"
    
    case "$command" in
        "")
            # 无参数时显示配置和帮助
            print_config_table
            print_help
            ;;
        show)
            print_config_table
            ;;
        theme)
            if [ -z "$value" ]; then
                # 显示当前主题
                local current
                current=$(get_config "CLAUDE_CODE_STATUSLINE_THEME" "$DEFAULT_THEME")
                echo -e "${CYAN}当前主题:${RESET} $current"
                echo -e "${DIM}可用主题: $THEMES${RESET}"
            else
                set_theme "$value"
            fi
            ;;
        layout)
            if [ -z "$value" ]; then
                local current
                current=$(get_config "CLAUDE_CODE_STATUSLINE_LAYOUT" "$DEFAULT_LAYOUT")
                echo -e "${CYAN}当前布局:${RESET} $current"
                echo -e "${DIM}可用布局: $LAYOUTS${RESET}"
            else
                set_layout "$value"
            fi
            ;;
        bar-style)
            if [ -z "$value" ]; then
                local current
                current=$(get_config "CLAUDE_CODE_STATUSLINE_BAR_STYLE" "$DEFAULT_BAR_STYLE")
                echo -e "${CYAN}当前进度条样式:${RESET} $current"
                echo -e "${DIM}可用样式: $BAR_STYLES${RESET}"
            else
                set_bar_style "$value"
            fi
            ;;
        max-width)
            if [ -z "$value" ]; then
                local current
                current=$(get_config "CLAUDE_CODE_STATUSLINE_MAX_WIDTH" "$DEFAULT_MAX_WIDTH")
                echo -e "${CYAN}当前最大宽度:${RESET} $current"
                echo -e "${DIM}应为正整数或 auto${RESET}"
            else
                set_max_width "$value"
            fi
            ;;
        reset)
            reset_config
            ;;
        help|--help|-h)
            print_help
            ;;
        *)
            echo -e "${RED}✗ 未知命令: $command${RESET}"
            print_help
            exit 1
            ;;
    esac
}

main "$@"
