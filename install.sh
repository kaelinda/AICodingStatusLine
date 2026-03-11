#!/usr/bin/env bash
# AICodingStatusLine 一键安装脚本
# 用法: ./install.sh [选项]
#   --theme <name>    设置主题 (default/forest/dracula/monokai/solarized/ocean/sunset/amber/rose)
#   --layout <mode>   设置布局 (compact/bars)
#   --bar-style <s>   设置进度条样式 (ascii/dots/squares)
#   --uninstall       卸载状态栏
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/statusline.sh"
TARGET_SCRIPT="$CLAUDE_DIR/statusline.sh"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { printf "${CYAN}▶${RESET} %s\n" "$1"; }
ok()    { printf "${GREEN}✔${RESET} %s\n" "$1"; }
warn()  { printf "${YELLOW}⚠${RESET} %s\n" "$1"; }
err()   { printf "${RED}✖${RESET} %s\n" "$1" >&2; }

# --- 参数解析 ---
THEME=""
LAYOUT=""
BAR_STYLE=""
UNINSTALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --theme)     THEME="$2";     shift 2 ;;
        --layout)    LAYOUT="$2";    shift 2 ;;
        --bar-style) BAR_STYLE="$2"; shift 2 ;;
        --uninstall) UNINSTALL=true; shift   ;;
        -h|--help)
            printf "${BOLD}AICodingStatusLine 安装脚本${RESET}\n\n"
            printf "用法: ./install.sh [选项]\n\n"
            printf "选项:\n"
            printf "  --theme <name>    主题: default/forest/dracula/monokai/solarized/ocean/sunset/amber/rose\n"
            printf "  --layout <mode>   布局: compact/bars\n"
            printf "  --bar-style <s>   进度条: ascii/dots/squares\n"
            printf "  --uninstall       卸载状态栏\n"
            printf "  -h, --help        显示此帮助\n"
            exit 0
            ;;
        *)
            err "未知选项: $1"
            exit 1
            ;;
    esac
done

# --- 前置检查 ---
check_deps() {
    local missing=()
    command -v jq  >/dev/null 2>&1 || missing+=("jq")
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "缺少依赖: ${missing[*]}"
        printf "  安装方式:\n"
        if [[ "$(uname)" == "Darwin" ]]; then
            printf "    brew install %s\n" "${missing[*]}"
        else
            printf "    sudo apt install %s  # 或对应包管理器\n" "${missing[*]}"
        fi
        printf "\n"
        read -rp "是否继续安装？(y/N) " ans
        [[ "$ans" =~ ^[Yy]$ ]] || exit 0
    fi
}

# --- 卸载 ---
do_uninstall() {
    info "正在卸载 AICodingStatusLine..."

    if [[ -f "$TARGET_SCRIPT" ]]; then
        rm -f "$TARGET_SCRIPT"
        ok "已删除 $TARGET_SCRIPT"
    fi

    if [[ -f "$SETTINGS_FILE" ]] && command -v jq >/dev/null 2>&1; then
        local tmp
        tmp=$(jq 'del(.statusLine)
            | del(.env.CLAUDE_CODE_STATUSLINE_THEME)
            | del(.env.CLAUDE_CODE_STATUSLINE_LAYOUT)
            | del(.env.CLAUDE_CODE_STATUSLINE_BAR_STYLE)
            | del(.env.CLAUDE_CODE_STATUSLINE_SEVEN_DAY_TIME_FORMAT)
            | if .env == {} then del(.env) else . end' "$SETTINGS_FILE")
        printf '%s\n' "$tmp" > "$SETTINGS_FILE"
        ok "已清理 settings.json"
    fi

    ok "卸载完成，重启 Claude Code 即可生效"
    exit 0
}

# --- 安装 ---
do_install() {
    printf "\n${BOLD}  AICodingStatusLine 安装程序${RESET}\n\n"

    # 检查源脚本
    if [[ ! -f "$SOURCE_SCRIPT" ]]; then
        err "找不到 statusline.sh，请在项目根目录运行此脚本"
        exit 1
    fi

    check_deps

    # 1. 创建目录
    mkdir -p "$CLAUDE_DIR"

    # 2. 复制脚本
    info "复制 statusline.sh → $TARGET_SCRIPT"
    cp -f "$SOURCE_SCRIPT" "$TARGET_SCRIPT"
    chmod +x "$TARGET_SCRIPT"
    ok "脚本已就位"

    # 3. 更新 settings.json
    info "更新 $SETTINGS_FILE"

    if [[ ! -f "$SETTINGS_FILE" ]]; then
        # 全新创建
        printf '{}' > "$SETTINGS_FILE"
    fi

    # 用 jq 安全合并，不覆盖已有配置
    local tmp
    tmp=$(jq --arg cmd "~/.claude/statusline.sh" '
        .statusLine = { "type": "command", "command": $cmd }
    ' "$SETTINGS_FILE")

    # 写入环境变量（仅当用户指定或原来没有时）
    if [[ -n "$THEME" ]]; then
        tmp=$(printf '%s' "$tmp" | jq --arg v "$THEME" '.env.CLAUDE_CODE_STATUSLINE_THEME = $v')
    fi
    if [[ -n "$LAYOUT" ]]; then
        tmp=$(printf '%s' "$tmp" | jq --arg v "$LAYOUT" '.env.CLAUDE_CODE_STATUSLINE_LAYOUT = $v')
    fi
    if [[ -n "$BAR_STYLE" ]]; then
        tmp=$(printf '%s' "$tmp" | jq --arg v "$BAR_STYLE" '.env.CLAUDE_CODE_STATUSLINE_BAR_STYLE = $v')
    fi

    printf '%s\n' "$tmp" > "$SETTINGS_FILE"
    ok "配置已更新"

    # 4. 完成
    printf "\n${GREEN}${BOLD}  安装完成！${RESET}\n\n"
    printf "  重启 Claude Code 即可看到新状态栏。\n\n"

    # 显示当前配置
    printf "  ${BOLD}当前配置:${RESET}\n"
    local cur_theme cur_layout cur_bar
    cur_theme=$(jq -r '.env.CLAUDE_CODE_STATUSLINE_THEME // "default"' "$SETTINGS_FILE")
    cur_layout=$(jq -r '.env.CLAUDE_CODE_STATUSLINE_LAYOUT // "compact"' "$SETTINGS_FILE")
    cur_bar=$(jq -r '.env.CLAUDE_CODE_STATUSLINE_BAR_STYLE // "ascii"' "$SETTINGS_FILE")
    printf "    主题: ${CYAN}%s${RESET}\n" "$cur_theme"
    printf "    布局: ${CYAN}%s${RESET}\n" "$cur_layout"
    printf "    进度条: ${CYAN}%s${RESET}\n\n" "$cur_bar"

    printf "  ${BOLD}自定义示例:${RESET}\n"
    printf "    ./install.sh --theme dracula --layout bars --bar-style dots\n\n"
}

# --- 入口 ---
if $UNINSTALL; then
    do_uninstall
else
    do_install
fi
