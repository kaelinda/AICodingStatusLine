#!/usr/bin/env bash
# AICodingStatusLine 一键安装脚本
# 用法: ./install.sh [选项]
#   --target <name>   安装目标 (claude/codex/codex-native/both)
#   --theme <name>    设置主题 (default/forest/dracula/monokai/solarized/ocean/sunset/amber/rose)
#   --layout <mode>   设置布局 (compact/bars)
#   --bar-style <s>   设置进度条样式 (ascii/dots/squares)
#   --with-hooks      为 Codex 安装实验性 hooks sidecar
#   --with-notify     为 Codex 安装 notify bridge
#   --uninstall       卸载状态栏
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
CODEX_DIR="$HOME/.codex"
CODEX_BIN_DIR="$CODEX_DIR/bin"
CODEX_CONFIG_FILE="$CODEX_DIR/config.toml"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/scripts/statusline.sh"
TARGET_SCRIPT="$CLAUDE_DIR/statusline.sh"
TMUX_LAUNCHER_SOURCE="$SCRIPT_DIR/scripts/codex_tmux.sh"
TMUX_STATUS_SOURCE="$SCRIPT_DIR/scripts/codex_tmux_status.sh"
CODEX_STATUSLINE_SOURCE="$SCRIPT_DIR/scripts/codex_statusline.sh"
CODEX_COMMON_SOURCE="$SCRIPT_DIR/scripts/codex_statusline_common.sh"
HOOK_SIDECAR_SOURCE="$SCRIPT_DIR/scripts/codex_hook_sidecar.sh"
NOTIFY_BRIDGE_SOURCE="$SCRIPT_DIR/scripts/codex_notify_bridge.sh"
TMUX_LAUNCHER_TARGET="$CODEX_BIN_DIR/codex-tmux"
TMUX_STATUS_TARGET="$CODEX_BIN_DIR/codex-tmux-status"
CODEX_STATUSLINE_TARGET="$CODEX_BIN_DIR/codex-statusline"
CODEX_COMMON_TARGET="$CODEX_BIN_DIR/codex-statusline-common.sh"
HOOK_SIDECAR_TARGET="$CODEX_BIN_DIR/codex-hook-sidecar"
NOTIFY_BRIDGE_TARGET="$CODEX_BIN_DIR/codex-notify-bridge"
CODEX_HOOKS_FILE="$CODEX_DIR/hooks.json"

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
WITH_HOOKS=false
WITH_NOTIFY=false
CODEX_NATIVE_STATUS_LINE='["model-with-reasoning", "context-remaining", "current-dir"]'

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)    TARGET="$2";    shift 2 ;;
        --theme)     THEME="$2";     shift 2 ;;
        --layout)    LAYOUT="$2";    shift 2 ;;
        --bar-style) BAR_STYLE="$2"; shift 2 ;;
        --with-hooks) WITH_HOOKS=true; shift ;;
        --with-notify) WITH_NOTIFY=true; shift ;;
        --uninstall) UNINSTALL=true; shift   ;;
        -h|--help)
            printf "${BOLD}AICodingStatusLine 安装脚本${RESET}\n\n"
            printf "用法: ./install.sh [选项]\n\n"
            printf "选项:\n"
            printf "  --target <name>   目标: claude/codex/codex-native/both\n"
            printf "  --theme <name>    主题: default/forest/dracula/monokai/solarized/ocean/sunset/amber/rose\n"
            printf "  --layout <mode>   布局: compact/bars\n"
            printf "  --bar-style <s>   进度条: ascii/dots/squares\n"
            printf "  --with-hooks      为 Codex 安装实验性 hooks sidecar\n"
            printf "  --with-notify     为 Codex 安装 notify bridge\n"
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
    claude|codex|codex-native|both) ;;
    *)
        err "未知目标: $TARGET"
        exit 1
        ;;
esac

upsert_toml_key() {
    local section="$1"
    local key="$2"
    local value="$3"

    mkdir -p "$CODEX_DIR"
    touch "$CODEX_CONFIG_FILE"

    local tmp
    tmp=$(mktemp)

    awk -v section="$section" -v key="$key" -v value="$value" '
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
    ' "$CODEX_CONFIG_FILE" > "$tmp"

    mv "$tmp" "$CODEX_CONFIG_FILE"
}

remove_toml_exact_key() {
    local section="$1"
    local key="$2"
    local value="$3"

    [[ -f "$CODEX_CONFIG_FILE" ]] || return 0

    local tmp
    tmp=$(mktemp)

    awk -v section="$section" -v key="$key" -v value="$value" '
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

        in_section && $0 == key " = " value {
            next
        }

        {
            print
        }
    ' "$CODEX_CONFIG_FILE" > "$tmp"

    mv "$tmp" "$CODEX_CONFIG_FILE"
}

upsert_toml_root_key() {
    local key="$1"
    local value="$2"

    mkdir -p "$CODEX_DIR"
    touch "$CODEX_CONFIG_FILE"

    local tmp
    tmp=$(mktemp)

    awk -v key="$key" -v value="$value" '
        BEGIN {
            wrote_key = 0
        }

        /^\[/ {
            if (!wrote_key) {
                print key " = " value
                print ""
                wrote_key = 1
            }
            print
            next
        }

        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
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
            if (!wrote_key) {
                if (NR > 0) {
                    print ""
                }
                print key " = " value
            }
        }
    ' "$CODEX_CONFIG_FILE" > "$tmp"

    mv "$tmp" "$CODEX_CONFIG_FILE"
}

remove_toml_root_exact_key() {
    local key="$1"
    local value="$2"

    [[ -f "$CODEX_CONFIG_FILE" ]] || return 0

    local tmp
    tmp=$(mktemp)

    awk -v key="$key" -v value="$value" '
        $0 == key " = " value {
            next
        }

        {
            print
        }
    ' "$CODEX_CONFIG_FILE" > "$tmp"

    mv "$tmp" "$CODEX_CONFIG_FILE"
}

upsert_codex_tui_status_line() {
    upsert_toml_key "tui" "status_line" "$CODEX_NATIVE_STATUS_LINE"
}

remove_codex_tui_status_line() {
    remove_toml_exact_key "tui" "status_line" "$CODEX_NATIVE_STATUS_LINE"
}

upsert_codex_notify_settings() {
    upsert_toml_root_key "notify" "[\"$NOTIFY_BRIDGE_TARGET\"]"
    upsert_toml_key "tui" "notifications" "true"
}

upsert_codex_notify_segment_setting() {
    upsert_toml_key "statusline" "show_notify_segment" "true"
}

remove_codex_notify_settings() {
    remove_toml_root_exact_key "notify" "[\"$NOTIFY_BRIDGE_TARGET\"]"
    remove_toml_exact_key "tui" "notifications" "true"
    remove_toml_exact_key "statusline" "show_notify_segment" "true"
}

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

check_codex_hook_deps() {
    if ! command -v jq >/dev/null 2>&1; then
        err "--with-hooks 需要 jq 来合并 ~/.codex/hooks.json"
        exit 1
    fi
}

upsert_codex_hook_feature_flag() {
    upsert_toml_key "features" "codex_hooks" "true"
}

upsert_codex_hook_segment_setting() {
    upsert_toml_key "statusline" "show_hook_segment" "true"
}

remove_codex_hook_settings() {
    remove_toml_exact_key "features" "codex_hooks" "true"
    remove_toml_exact_key "statusline" "show_hook_segment" "true"
}

upsert_codex_hooks_json() {
    local tmp existing

    mkdir -p "$CODEX_DIR"
    if [[ -f "$CODEX_HOOKS_FILE" ]]; then
        existing=$(cat "$CODEX_HOOKS_FILE")
    else
        existing='{}'
    fi

    tmp=$(mktemp)
    printf '%s' "$existing" | jq \
        --arg cmd "$HOOK_SIDECAR_TARGET" \
        'def prune_existing:
            map(select(((.hooks // []) | any(.command == $cmd)) | not));

        .hooks = (.hooks // {})
        | .hooks.SessionStart = ((.hooks.SessionStart // []) | prune_existing + [{
            matcher: "startup|resume",
            hooks: [{
                type: "command",
                command: $cmd,
                statusMessage: "AICodingStatusLine syncing session state"
            }]
        }])
        | .hooks.PreToolUse = ((.hooks.PreToolUse // []) | prune_existing + [{
            matcher: "Bash",
            hooks: [{
                type: "command",
                command: $cmd,
                statusMessage: "AICodingStatusLine capturing Bash start"
            }]
        }])
        | .hooks.PostToolUse = ((.hooks.PostToolUse // []) | prune_existing + [{
            matcher: "Bash",
            hooks: [{
                type: "command",
                command: $cmd,
                statusMessage: "AICodingStatusLine capturing Bash result"
            }]
        }])
        | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | prune_existing + [{
            hooks: [{
                type: "command",
                command: $cmd
            }]
        }])
        | .hooks.Stop = ((.hooks.Stop // []) | prune_existing + [{
            hooks: [{
                type: "command",
                command: $cmd
            }]
        }])' > "$tmp"

    mv "$tmp" "$CODEX_HOOKS_FILE"
}

remove_codex_hooks_json() {
    [[ -f "$CODEX_HOOKS_FILE" ]] || return 0

    local tmp
    tmp=$(mktemp)

    jq --arg cmd "$HOOK_SIDECAR_TARGET" '
        if .hooks then
            .hooks |= (
                to_entries
                | map(
                    .value |= ((. // []) | map(select(((.hooks // []) | any(.command == $cmd)) | not)))
                )
                | map(select((.value | length) > 0))
                | from_entries
            )
            | if (.hooks | length) == 0 then del(.hooks) else . end
        else
            .
        end
    ' "$CODEX_HOOKS_FILE" > "$tmp"

    mv "$tmp" "$CODEX_HOOKS_FILE"
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
        tmp=$(printf '%s' "$tmp" | jq --arg v "$THEME" '.env.CLAUDE_CODE_STATUSLINE_THEME = $v')
    fi
    if [[ -n "$LAYOUT" ]]; then
        tmp=$(printf '%s' "$tmp" | jq --arg v "$LAYOUT" '.env.CLAUDE_CODE_STATUSLINE_LAYOUT = $v')
    fi
    if [[ -n "$BAR_STYLE" ]]; then
        tmp=$(printf '%s' "$tmp" | jq --arg v "$BAR_STYLE" '.env.CLAUDE_CODE_STATUSLINE_BAR_STYLE = $v')
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

install_codex_hooks() {
    local enable_hook_segment="${1:-0}"

    if [[ ! -f "$HOOK_SIDECAR_SOURCE" ]]; then
        err "找不到 Codex hooks sidecar 脚本，请确认仓库文件完整"
        exit 1
    fi

    check_codex_hook_deps
    mkdir -p "$CODEX_BIN_DIR"

    info "复制 Codex hooks sidecar → $HOOK_SIDECAR_TARGET"
    cp -f "$HOOK_SIDECAR_SOURCE" "$HOOK_SIDECAR_TARGET"
    chmod +x "$HOOK_SIDECAR_TARGET"

    info "更新 $CODEX_HOOKS_FILE"
    upsert_codex_hooks_json

    info "开启 $CODEX_CONFIG_FILE 中的实验性 hooks"
    upsert_codex_hook_feature_flag
    if [[ "$enable_hook_segment" == "1" ]]; then
        upsert_codex_hook_segment_setting
    fi

    ok "Codex 实验性 hooks sidecar 已安装"
}

install_codex_notify() {
    local enable_notify_segment="${1:-0}"

    if [[ ! -f "$NOTIFY_BRIDGE_SOURCE" ]]; then
        err "找不到 Codex notify bridge 脚本，请确认仓库文件完整"
        exit 1
    fi

    mkdir -p "$CODEX_BIN_DIR"

    info "复制 Codex notify bridge → $NOTIFY_BRIDGE_TARGET"
    cp -f "$NOTIFY_BRIDGE_SOURCE" "$NOTIFY_BRIDGE_TARGET"
    chmod +x "$NOTIFY_BRIDGE_TARGET"

    info "更新 $CODEX_CONFIG_FILE 中的 notify 配置"
    upsert_codex_notify_settings
    if [[ "$enable_notify_segment" == "1" ]]; then
        upsert_codex_notify_segment_setting
    fi

    ok "Codex notify bridge 已安装"
}

install_codex_native() {
    if [[ -n "$THEME" || -n "$LAYOUT" || -n "$BAR_STYLE" ]]; then
        warn "codex-native 使用 Codex 原生 status line，忽略 --theme / --layout / --bar-style"
    fi

    info "更新 $CODEX_CONFIG_FILE 的 [tui].status_line"
    upsert_codex_tui_status_line
    ok "Codex 原生状态栏已配置"
}

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

    if [[ -f "$HOOK_SIDECAR_TARGET" ]]; then
        rm -f "$HOOK_SIDECAR_TARGET"
        ok "已删除 $HOOK_SIDECAR_TARGET"
    fi

    if [[ -f "$NOTIFY_BRIDGE_TARGET" ]]; then
        rm -f "$NOTIFY_BRIDGE_TARGET"
        ok "已删除 $NOTIFY_BRIDGE_TARGET"
    fi

    if [[ -f "$CODEX_HOOKS_FILE" ]]; then
        remove_codex_hooks_json
        ok "已清理 $CODEX_HOOKS_FILE 中的 AICodingStatusLine hooks"
    fi

    if [[ -f "$CODEX_CONFIG_FILE" ]]; then
        remove_codex_tui_status_line
        remove_codex_hook_settings
        remove_codex_notify_settings
        ok "已清理 $CODEX_CONFIG_FILE 中由 AICodingStatusLine 托管的 Codex 配置"
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
        codex-native)
            install_codex_native
            ;;
        both)
            install_claude
            install_codex_tmux
            ;;
    esac

    if $WITH_HOOKS; then
        if [[ "$TARGET" == "claude" ]]; then
            warn "--with-hooks 仅对 Codex 目标生效，已忽略"
        else
            if [[ "$TARGET" == "codex" || "$TARGET" == "both" ]]; then
                install_codex_hooks 1
            else
                install_codex_hooks 0
            fi
        fi
    fi

    if $WITH_NOTIFY; then
        if [[ "$TARGET" == "claude" ]]; then
            warn "--with-notify 仅对 Codex 目标生效，已忽略"
        else
            if [[ "$TARGET" == "codex" || "$TARGET" == "both" ]]; then
                install_codex_notify 1
            else
                install_codex_notify 0
            fi
        fi
    fi

    printf "\n${GREEN}${BOLD}  安装完成！${RESET}\n\n"
    printf "  安装目标: ${CYAN}%s${RESET}\n" "$TARGET"

    if [[ "$TARGET" == "claude" || "$TARGET" == "both" ]]; then
        printf "  Claude Code: 重启后即可看到新状态栏。\n"
        printf "  状态栏脚本: ${CYAN}%s${RESET}\n" "$TARGET_SCRIPT"

        local cur_theme cur_layout cur_bar
        cur_theme=$(jq -r '.env.CLAUDE_CODE_STATUSLINE_THEME // "default"' "$SETTINGS_FILE")
        cur_layout=$(jq -r '.env.CLAUDE_CODE_STATUSLINE_LAYOUT // "bars"' "$SETTINGS_FILE")
        cur_bar=$(jq -r '.env.CLAUDE_CODE_STATUSLINE_BAR_STYLE // "ascii"' "$SETTINGS_FILE")
        printf "  主题: ${CYAN}%s${RESET}\n" "$cur_theme"
        printf "  布局: ${CYAN}%s${RESET}\n" "$cur_layout"
        printf "  进度条: ${CYAN}%s${RESET}\n" "$cur_bar"
    fi

    if [[ "$TARGET" == "codex" || "$TARGET" == "both" ]]; then
        printf "  Codex tmux: 通过 ${CYAN}~/.codex/bin/codex-tmux${RESET} 启动。\n"
        printf "  启动器: ${CYAN}%s${RESET}\n" "$TMUX_LAUNCHER_TARGET"
        printf "  状态栏: ${CYAN}%s${RESET}\n" "$CODEX_STATUSLINE_TARGET"
    fi

    if [[ "$TARGET" == "codex-native" ]]; then
        printf "  Codex 原生状态栏: 已写入 ${CYAN}%s${RESET}\n" "$CODEX_CONFIG_FILE"
        printf "  当前项: ${CYAN}%s${RESET}\n" "$CODEX_NATIVE_STATUS_LINE"
    fi

    if $WITH_HOOKS && [[ "$TARGET" != "claude" ]]; then
        printf "  Codex hooks: 已安装实验性 sidecar ${CYAN}%s${RESET}\n" "$HOOK_SIDECAR_TARGET"
        printf "  hooks.json: ${CYAN}%s${RESET}\n" "$CODEX_HOOKS_FILE"
    fi

    printf "\n  ${BOLD}示例:${RESET}\n"
    printf "    ./install.sh --target both --theme dracula --layout bars --bar-style dots\n\n"
}

if $UNINSTALL; then
    do_uninstall
else
    do_install
fi
