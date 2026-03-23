#!/bin/bash
#
# post-install.sh - AICoding StatusLine 插件安装后钩子
# 
# 此脚本在插件安装后自动执行，完成以下任务：
# 1. 复制 statusline.sh 到 ~/.claude/
# 2. 检查依赖 (jq, curl)，缺失则退出
# 3. 更新 ~/.claude/settings.json 的 statusLine 配置

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
echo -e "\n${YELLOW}[1/3] 复制 statusline.sh 到 ~/.claude/${NC}"
mkdir -p ~/.claude
cp "$SCRIPT_DIR/statusline.sh" ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
echo -e "${GREEN}✓ 已复制 statusline.sh 到 ~/.claude/${NC}"

# 步骤 2: 检查并安装依赖
echo -e "\n${YELLOW}[2/3] 检查依赖${NC}"

# 检查 curl
MISSING_DEPS=()
if ! command -v curl &> /dev/null; then
    echo -e "${RED}✗ curl 未安装${NC}"
    MISSING_DEPS+=("curl")
else
    echo -e "${GREEN}✓ curl 已安装: $(curl --version | head -1)${NC}"
fi

# 检查 jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}✗ jq 未安装${NC}"
    MISSING_DEPS+=("jq")
else
    echo -e "${GREEN}✓ jq 已安装: $(jq --version)${NC}"
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo -e "${RED}缺少必要依赖: ${MISSING_DEPS[*]}${NC}"
    echo "  请安装后重新运行:"
    echo "    - macOS: brew install ${MISSING_DEPS[*]}"
    echo "    - Ubuntu/Debian: sudo apt-get install ${MISSING_DEPS[*]}"
    echo "    - CentOS/RHEL: sudo yum install ${MISSING_DEPS[*]}"
    exit 1
fi

# 步骤 3: 更新 ~/.claude/settings.json
echo -e "\n${YELLOW}[3/3] 配置 Claude Code settings.json${NC}"
SETTINGS_FILE=~/.claude/settings.json

if [ -f "$SETTINGS_FILE" ]; then
    # 备份现有配置
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%Y%m%d%H%M%S)"
    echo -e "${GREEN}✓ 已备份现有 settings.json${NC}"
fi

# 创建或更新 settings.json
if [ -f "$SETTINGS_FILE" ]; then
    # 使用 jq 更新 statusLine.command
    tmp_file=$(mktemp)
    jq '.statusLine = { "type": "command", "command": "~/.claude/statusline.sh" }' "$SETTINGS_FILE" > "$tmp_file" 2>/dev/null || true
    if [ -s "$tmp_file" ]; then
        mv "$tmp_file" "$SETTINGS_FILE"
        echo -e "${GREEN}✓ 已更新 statusLine 配置${NC}"
    else
        rm -f "$tmp_file"
        echo -e "${YELLOW}! 无法更新 settings.json，请手动配置${NC}"
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

# 完成
echo -e "\n${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   AICoding StatusLine 插件安装完成！                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "配置文件位置:"
echo "  - 脚本: ~/.claude/statusline.sh"
echo "  - 设置: ~/.claude/settings.json"
echo ""
echo "自定义配置:"
echo "  通过环境变量配置主题和布局，详见 README.md"
echo "  例: CLAUDE_CODE_STATUSLINE_THEME=forest"
echo ""
echo "重新启动 Claude Code 以使状态栏生效。"
