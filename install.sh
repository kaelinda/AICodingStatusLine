#!/usr/bin/env bash
# AICodingStatusLine 一键安装脚本
# 用法: ./install.sh [选项]
#   --target <name>   安装目标 (claude/codex/both)
#   --theme <name>    设置主题 (default/forest/dracula/monokai/solarized/ocean/sunset/amber/rose)
#   --layout <mode>   设置布局 (compact/bars)
#   --bar-style <s>   设置进度条样式 (ascii/dots/squares)
#   其他 Claude 高级选项请在 ~/.claude/settings.json 的 env 中设置
#   推荐使用共享键名: STATUSLINE_MODE / STATUSLINE_SHOW_* / STATUSLINE_THEME
#   --uninstall       卸载状态栏
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
CODEX_DIR="$HOME/.codex"
CODEX_BIN_DIR="$CODEX_DIR/bin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/statusline.sh"
TARGET_SCRIPT="$CLAUDE_DIR/statusline.sh"
CLAUDE_COMMON_TARGET="$CLAUDE_DIR/codex_statusline_common.sh"
TMUX_LAUNCHER_SOURCE="$SCRIPT_DIR/codex_tmux.sh"
TMUX_STATUS_SOURCE="$SCRIPT_DIR/codex_tmux_status.sh"
CODEX_STATUSLINE_SOURCE="$SCRIPT_DIR/codex_statusline.sh"
CODEX_COMMON_SOURCE="$SCRIPT_DIR/codex_statusline_common.sh"
TMUX_LAUNCHER_TARGET="$CODEX_BIN_DIR/codex-tmux"
TMUX_STATUS_TARGET="$CODEX_BIN_DIR/codex-tmux-status"
CODEX_STATUSLINE_TARGET="$CODEX_BIN_DIR/codex-statusline"
CODEX_COMMON_TARGET="$CODEX_BIN_DIR/codex-statusline-common.sh"

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

TARGET="claude"
THEME=""
LAYOUT=""
BAR_STYLE=""
UNINSTALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)    TARGET="$2";    shift 2 ;;
        --theme)     THEME="$2";     shift 2 ;;
        --layout)    LAYOUT="$2";    shift 2 ;;
        --bar-style) BAR_STYLE="$2"; shift 2 ;;
        --uninstall) UNINSTALL=true; shift   ;;
        -h|--help)
            printf "${BOLD}AICodingStatusLine 安装脚本${RESET}\n\n"
            printf "用法: ./install.sh [选项]\n\n"
            printf "选项:\n"
            printf "  --target <name>   目标: claude/codex/both\n"
            printf "  --theme <name>    主题: default/forest/dracula/monokai/solarized/ocean/sunset/amber/rose\n"
            printf "  --layout <mode>   布局: compact/bars\n"
            printf "  --bar-style <s>   进度条: ascii/dots/squares\n"
            printf "  提示: 其他 Claude 高级配置请写入 ~/.claude/settings.json 的 env\n"
            printf "        推荐共享键名: STATUSLINE_MODE / STATUSLINE_SHOW_GIT_LINE / STATUSLINE_SHOW_OVERVIEW_LINE / STATUSLINE_SHOW_HOURLY_BAR / STATUSLINE_SHOW_DAILY_BAR\n"
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

case "$TARGET" in
    claude|codex|both) ;;
    *)
        err "未知目标: $TARGET"
        exit 1
        ;;
esac

check_claude_deps() {
    local missing=()
    command -v jq >/dev/null 2>&1 || missing+=("jq")
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

install_claude() {
    if [[ ! -f "$SOURCE_SCRIPT" ]]; then
        err "找不到 statusline.sh，请在项目根目录运行此脚本"
        exit 1
    fi

    check_claude_deps
    mkdir -p "$CLAUDE_DIR"

    info "复制 statusline.sh → $TARGET_SCRIPT"
    cp -f "$SOURCE_SCRIPT" "$TARGET_SCRIPT"
    chmod +x "$TARGET_SCRIPT"

    info "复制共享 helper → $CLAUDE_COMMON_TARGET"
    cp -f "$CODEX_COMMON_SOURCE" "$CLAUDE_COMMON_TARGET"
    chmod +x "$CLAUDE_COMMON_TARGET"
    ok "Claude 状态栏脚本已就位"

    info "更新 $SETTINGS_FILE"
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        printf '{}' > "$SETTINGS_FILE"
    fi

    local tmp
    tmp=$(jq --arg cmd "~/.claude/statusline.sh" '
        .statusLine = { "type": "command", "command": $cmd }
    ' "$SETTINGS_FILE")

    if [[ -n "$THEME" ]]; then
        tmp=$(printf '%s' "$tmp" | jq --arg v "$THEME" '.env.STATUSLINE_THEME = $v')
    fi
    if [[ -n "$LAYOUT" ]]; then
        tmp=$(printf '%s' "$tmp" | jq --arg v "$LAYOUT" '.env.STATUSLINE_MODE = $v')
    fi
    if [[ -n "$BAR_STYLE" ]]; then
        tmp=$(printf '%s' "$tmp" | jq --arg v "$BAR_STYLE" '.env.STATUSLINE_BAR_STYLE = $v')
    fi

    printf '%s\n' "$tmp" > "$SETTINGS_FILE"
    ok "Claude 配置已更新"
}

install_codex_tmux() {
    if [[ ! -f "$TMUX_LAUNCHER_SOURCE" || ! -f "$CODEX_STATUSLINE_SOURCE" || ! -f "$CODEX_COMMON_SOURCE" ]]; then
        err "找不到 Codex tmux 脚本，请确认仓库文件完整"
        exit 1
    fi

    mkdir -p "$CODEX_BIN_DIR"

    info "复制 Codex tmux 启动器 → $TMUX_LAUNCHER_TARGET"
    cp -f "$TMUX_LAUNCHER_SOURCE" "$TMUX_LAUNCHER_TARGET"
    chmod +x "$TMUX_LAUNCHER_TARGET"

    info "复制 Codex 状态栏脚本 → $CODEX_STATUSLINE_TARGET"
    cp -f "$CODEX_STATUSLINE_SOURCE" "$CODEX_STATUSLINE_TARGET"
    chmod +x "$CODEX_STATUSLINE_TARGET"

    info "复制 Codex 共享脚本 → $CODEX_COMMON_TARGET"
    cp -f "$CODEX_COMMON_SOURCE" "$CODEX_COMMON_TARGET"
    chmod +x "$CODEX_COMMON_TARGET"

    info "复制 Codex tmux 状态脚本（兼容层）→ $TMUX_STATUS_TARGET"
    cp -f "$TMUX_STATUS_SOURCE" "$TMUX_STATUS_TARGET"
    chmod +x "$TMUX_STATUS_TARGET"

    ok "Codex tmux 脚本已安装"
}

do_uninstall() {
    info "正在卸载 AICodingStatusLine..."

    if [[ -f "$TARGET_SCRIPT" ]]; then
        rm -f "$TARGET_SCRIPT"
        ok "已删除 $TARGET_SCRIPT"
    fi

    if [[ -f "$CLAUDE_COMMON_TARGET" ]]; then
        rm -f "$CLAUDE_COMMON_TARGET"
        ok "已删除 $CLAUDE_COMMON_TARGET"
    fi

    if [[ -f "$SETTINGS_FILE" ]] && command -v jq >/dev/null 2>&1; then
        local tmp
        tmp=$(jq 'del(.statusLine)
            | del(.env.STATUSLINE_THEME)
            | del(.env.STATUSLINE_MODE)
            | del(.env.STATUSLINE_BAR_STYLE)
            | del(.env.STATUSLINE_SHOW_GIT_LINE)
            | del(.env.STATUSLINE_SHOW_OVERVIEW_LINE)
            | del(.env.STATUSLINE_SHOW_HOURLY_BAR)
            | del(.env.STATUSLINE_SHOW_DAILY_BAR)
            | del(.env.STATUSLINE_MAX_WIDTH)
            | del(.env.STATUSLINE_DAILY_TIME_FORMAT)
            | del(.env.STATUSLINE_SEVEN_DAY_TIME_FORMAT)
            | del(.env.CLAUDE_CODE_STATUSLINE_THEME)
            | del(.env.CLAUDE_CODE_STATUSLINE_LAYOUT)
            | del(.env.CLAUDE_CODE_STATUSLINE_BAR_STYLE)
            | del(.env.CLAUDE_CODE_STATUSLINE_SHOW_GIT_LINE)
            | del(.env.CLAUDE_CODE_STATUSLINE_SHOW_OVERVIEW_LINE)
            | del(.env.CLAUDE_CODE_STATUSLINE_SHOW_HOURLY_BAR)
            | del(.env.CLAUDE_CODE_STATUSLINE_SHOW_DAILY_BAR)
            | del(.env.CLAUDE_CODE_STATUSLINE_MAX_WIDTH)
            | del(.env.CLAUDE_CODE_STATUSLINE_SEVEN_DAY_TIME_FORMAT)
            | if .env == {} then del(.env) else . end' "$SETTINGS_FILE")
        printf '%s\n' "$tmp" > "$SETTINGS_FILE"
        ok "已清理 settings.json"
    fi

    if [[ -f "$TMUX_LAUNCHER_TARGET" ]]; then
        rm -f "$TMUX_LAUNCHER_TARGET"
        ok "已删除 $TMUX_LAUNCHER_TARGET"
    fi

    if [[ -f "$TMUX_STATUS_TARGET" ]]; then
        rm -f "$TMUX_STATUS_TARGET"
        ok "已删除 $TMUX_STATUS_TARGET"
    fi

    if [[ -f "$CODEX_STATUSLINE_TARGET" ]]; then
        rm -f "$CODEX_STATUSLINE_TARGET"
        ok "已删除 $CODEX_STATUSLINE_TARGET"
    fi

    if [[ -f "$CODEX_COMMON_TARGET" ]]; then
        rm -f "$CODEX_COMMON_TARGET"
        ok "已删除 $CODEX_COMMON_TARGET"
    fi

    rmdir "$CODEX_BIN_DIR" 2>/dev/null || true
    rmdir "$CODEX_DIR" 2>/dev/null || true

    ok "卸载完成"
    exit 0
}

do_install() {
    printf "\n${BOLD}  AICodingStatusLine 安装程序${RESET}\n\n"

    case "$TARGET" in
        claude)
            install_claude
            ;;
        codex)
            install_codex_tmux
            ;;
        both)
            install_claude
            install_codex_tmux
            ;;
    esac

    printf "\n${GREEN}${BOLD}  安装完成！${RESET}\n\n"
    printf "  安装目标: ${CYAN}%s${RESET}\n" "$TARGET"

    if [[ "$TARGET" == "claude" || "$TARGET" == "both" ]]; then
        printf "  Claude Code: 重启后即可看到新状态栏。\n"
        printf "  状态栏脚本: ${CYAN}%s${RESET}\n" "$TARGET_SCRIPT"

        local cur_theme cur_layout cur_bar
        cur_theme=$(jq -r '.env.STATUSLINE_THEME // .env.CLAUDE_CODE_STATUSLINE_THEME // "default"' "$SETTINGS_FILE")
        cur_layout=$(jq -r '.env.STATUSLINE_MODE // .env.CLAUDE_CODE_STATUSLINE_LAYOUT // "compact"' "$SETTINGS_FILE")
        cur_bar=$(jq -r '.env.STATUSLINE_BAR_STYLE // .env.CLAUDE_CODE_STATUSLINE_BAR_STYLE // "ascii"' "$SETTINGS_FILE")
        printf "  主题: ${CYAN}%s${RESET}\n" "$cur_theme"
        printf "  布局: ${CYAN}%s${RESET}\n" "$cur_layout"
        printf "  进度条: ${CYAN}%s${RESET}\n" "$cur_bar"
        printf "  高级项: 可在 ${CYAN}%s${RESET} 的 env 中继续设置 STATUSLINE_SHOW_GIT_LINE / STATUSLINE_SHOW_OVERVIEW_LINE / STATUSLINE_SHOW_HOURLY_BAR / STATUSLINE_SHOW_DAILY_BAR / STATUSLINE_MAX_WIDTH\n" "$SETTINGS_FILE"
    fi

    if [[ "$TARGET" == "codex" || "$TARGET" == "both" ]]; then
        printf "  Codex tmux: 通过 ${CYAN}~/.codex/bin/codex-tmux${RESET} 启动。\n"
        printf "  启动器: ${CYAN}%s${RESET}\n" "$TMUX_LAUNCHER_TARGET"
        printf "  状态栏: ${CYAN}%s${RESET}\n" "$CODEX_STATUSLINE_TARGET"
    fi

    printf "\n  ${BOLD}示例:${RESET}\n"
    printf "    ./install.sh --target both --theme dracula --layout bars --bar-style dots\n\n"
}

if $UNINSTALL; then
    do_uninstall
else
    do_install
fi
