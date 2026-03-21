#!/bin/bash
#
# post-install.sh - AICoding StatusLine 插件安装后钩子
# 
# 此脚本在插件安装后自动执行，完成以下任务：
# 1. 复制 statusline.sh 到 ~/.claude/
# 2. 检查并安装依赖 (jq, curl)
# 3. 更新 ~/.claude/settings.json 的 statusLine.command
# 4. 设置默认配置

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   AICoding StatusLine - 插件安装后配置                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"

# 步骤 1: 复制 statusline.sh 到 ~/.claude/
echo -e "\n${YELLOW}[1/4] 复制 statusline.sh 到 ~/.claude/${NC}"
mkdir -p ~/.claude
cp "$SCRIPT_DIR/statusline.sh" ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
echo -e "${GREEN}✓ 已复制 statusline.sh 到 ~/.claude/${NC}"

# 步骤 2: 检查并安装依赖
echo -e "\n${YELLOW}[2/4] 检查依赖${NC}"

# 检查 curl
if ! command -v curl &> /dev/null; then
    echo -e "${RED}✗ curl 未安装${NC}"
    echo "  请安装 curl: "
    echo "    - macOS: brew install curl"
    echo "    - Ubuntu/Debian: sudo apt-get install curl"
    echo "    - CentOS/RHEL: sudo yum install curl"
else
    echo -e "${GREEN}✓ curl 已安装: $(curl --version | head -1)${NC}"
fi

# 检查 jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}✗ jq 未安装${NC}"
    echo "  请安装 jq: "
    echo "    - macOS: brew install jq"
    echo "    - Ubuntu/Debian: sudo apt-get install jq"
    echo "    - CentOS/RHEL: sudo yum install jq"
else
    echo -e "${GREEN}✓ jq 已安装: $(jq --version)${NC}"
fi

# 步骤 3: 更新 ~/.claude/settings.json
echo -e "\n${YELLOW}[3/4] 配置 Claude Code settings.json${NC}"
SETTINGS_FILE=~/.claude/settings.json

if [ -f "$SETTINGS_FILE" ]; then
    # 备份现有配置
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%Y%m%d%H%M%S)"
    echo -e "${GREEN}✓ 已备份现有 settings.json${NC}"
fi

# 创建或更新 settings.json
if [ -f "$SETTINGS_FILE" ]; then
    # 使用 jq 更新 statusLine.command
    if command -v jq &> /dev/null; then
        tmp_file=$(mktemp)
        jq '.statusLine.command = "~/.claude/statusline.sh"' "$SETTINGS_FILE" > "$tmp_file" 2>/dev/null || true
        if [ -s "$tmp_file" ]; then
            mv "$tmp_file" "$SETTINGS_FILE"
            echo -e "${GREEN}✓ 已更新 statusLine.command${NC}"
        else
            rm -f "$tmp_file"
            echo -e "${YELLOW}! 无法更新 settings.json，请手动配置${NC}"
        fi
    else
        echo -e "${YELLOW}! jq 未安装，请手动更新 settings.json:${NC}"
        echo '  添加或修改: "statusLine": { "command": "~/.claude/statusline.sh" }'
    fi
else
    # 创建新的 settings.json
    cat > "$SETTINGS_FILE" << 'EOF'
{
  "statusLine": {
    "command": "~/.claude/statusline.sh"
  }
}
EOF
    echo -e "${GREEN}✓ 已创建 settings.json${NC}"
fi

# 步骤 4: 设置默认配置
echo -e "\n${YELLOW}[4/4] 设置默认配置${NC}"

# 创建默认配置文件
CONFIG_FILE=~/.claude/statusline.conf
if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << 'EOF'
# AICoding StatusLine 默认配置
# 主题: dots (圆点主题) 或 squares (方块主题)
STATUSLINE_THEME="${STATUSLINE_THEME:-dots}"

# 显示用量信息
STATUSLINE_SHOW_USAGE="${STATUSLINE_SHOW_USAGE:-true}"

# 显示进度条
STATUSLINE_SHOW_PROGRESS="${STATUSLINE_SHOW_PROGRESS:-true}"

# 显示模型名称
STATUSLINE_SHOW_MODEL="${STATUSLINE_SHOW_MODEL:-true}"
EOF
    echo -e "${GREEN}✓ 已创建默认配置文件: $CONFIG_FILE${NC}"
else
    echo -e "${GREEN}✓ 配置文件已存在: $CONFIG_FILE${NC}"
fi

# 完成
echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✓ AICoding StatusLine 插件安装完成！                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "配置文件位置:"
echo "  - 脚本: ~/.claude/statusline.sh"
echo "  - 配置: ~/.claude/statusline.conf"
echo "  - 设置: ~/.claude/settings.json"
echo ""
echo "自定义配置:"
echo "  编辑 ~/.claude/statusline.conf 更改主题、用量显示等"
echo ""
echo "重新启动 Claude Code 以使状态栏生效。"
