#!/bin/bash
#
# post-install.sh - AICoding StatusLine 插件 SessionStart 钩子
#
# 幂等脚本：检查 ~/.claude/statusline.sh 是否已安装且为最新版本，
# 仅在需要时执行复制和配置。作为 SessionStart hook 每次会话启动时运行。

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/statusline.sh"
TARGET=~/.claude/statusline.sh
SETTINGS_FILE=~/.claude/settings.json
STAMP_FILE=~/.claude/.statusline-installed

# 快速路径：源文件和目标一致且 settings 已配置 statusLine，直接退出
if [ -f "$TARGET" ] && [ -f "$STAMP_FILE" ] && \
   cmp -s "$SOURCE" "$TARGET" 2>/dev/null && \
   [ -f "$SETTINGS_FILE" ] && \
   jq -e '.statusLine.command == "~/.claude/statusline.sh"' "$SETTINGS_FILE" >/dev/null 2>&1; then
    exit 0
fi

# --- 以下仅在首次安装或脚本有更新时执行 ---

# 检查依赖
for dep in jq curl; do
    if ! command -v "$dep" &> /dev/null; then
        echo "[aicoding-statusline] 缺少依赖: $dep，请先安装" >&2
        exit 1
    fi
done

# 复制脚本
mkdir -p ~/.claude
cp "$SOURCE" "$TARGET"
chmod +x "$TARGET"

# 配置 settings.json（仅当 statusLine 未配置时）
if [ -f "$SETTINGS_FILE" ]; then
    current_cmd=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE" 2>/dev/null)
    if [ "$current_cmd" != "~/.claude/statusline.sh" ]; then
        tmp_file=$(mktemp)
        jq '.statusLine = { "type": "command", "command": "~/.claude/statusline.sh" }' "$SETTINGS_FILE" > "$tmp_file" 2>/dev/null
        if [ -s "$tmp_file" ]; then
            mv "$tmp_file" "$SETTINGS_FILE"
        else
            rm -f "$tmp_file"
        fi
    fi
else
    cat > "$SETTINGS_FILE" << 'SETTINGSEOF'
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
SETTINGSEOF
fi

# 写入安装标记
date +%s > "$STAMP_FILE"

echo "[aicoding-statusline] 状态栏已安装/更新到 ~/.claude/statusline.sh"
