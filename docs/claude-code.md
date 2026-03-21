# Claude Code 状态栏 — 安装与配置

通过 Claude Code 原生 `statusLine.command` hook 驱动，从 stdin 接收 JSON 数据，调用 Anthropic API 获取用量信息，渲染为 ANSI 彩色文本。

---

## 前置依赖

| 工具 | 用途 |
|------|------|
| `jq` | 解析 JSON |
| `curl` | 从 Anthropic API 获取用量数据 |
| Claude Code | 需 OAuth 认证（Pro/Max 订阅） |

> Windows 用户请使用 `statusline.ps1`（需 PowerShell 5.1+ 和 `git`），不要使用 bash 脚本。

---

## 安装

### 方式一：一键安装脚本（推荐）

```bash
git clone https://github.com/kaelinda/AICodingStatusLine.git
cd AICodingStatusLine
./install.sh
```

默认只安装 Claude Code 状态栏。可追加选项：

```bash
# 指定主题、布局和进度条样式
./install.sh --theme dracula --layout bars --bar-style dots

# 查看帮助
./install.sh --help

# 卸载
./install.sh --uninstall
```

### 方式二：让 Claude 帮你装

复制 `statusline.sh` 和 `codex_statusline_common.sh`（Windows 用 `statusline.ps1`）的内容，或直接使用安装脚本；如果只提供 bash 主脚本而没有共享 helper，Claude 无法正常渲染状态栏。

> Use this script as my status bar

Claude Code 会自动保存脚本并配置 `settings.json`，无需手动操作。

### 方式三：手动安装

#### macOS / Linux

```bash
# 1. 复制脚本和共享 helper 到 Claude 配置目录
cp statusline.sh ~/.claude/statusline.sh
cp codex_statusline_common.sh ~/.claude/codex_statusline_common.sh
chmod +x ~/.claude/statusline.sh
chmod +x ~/.claude/codex_statusline_common.sh

# 2. 配置 settings.json（如文件已存在，手动合并即可）
cat <<'EOF' >> ~/.claude/settings.json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
EOF

# 3. 重启 Claude Code
```

#### Windows

```powershell
# 1. 复制脚本
Copy-Item statusline.ps1 "$env:USERPROFILE\.claude\statusline.ps1"
```

在 `%USERPROFILE%\.claude\settings.json` 中添加：

**PowerShell / CMD 环境：**

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -File \"%USERPROFILE%\\.claude\\statusline.ps1\""
  }
}
```

**Git Bash / WSL 环境：**

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -File \"$USERPROFILE\\.claude\\statusline.ps1\""
  }
}
```

> **注意：** CMD/PowerShell 中使用 `%USERPROFILE%`，bash 中使用 `$USERPROFILE`。两种语法不可混用。

重启 Claude Code 即可生效。

---

## 显示段落

| 段落 | 含义 | 示例 |
|------|------|------|
| **Model** | 当前模型名称 | `Opus 4.6` |
| **CWD@Branch** | 当前目录名 + Git 分支，仓库有改动时追加 `(+N -N)` | `myapp@main (+3 -1)` |
| **ctx** | 已用 / 总计 Context Window Token 数 + 百分比 | `ctx 15k/200k 7%` |
| **eff** | 推理努力等级 | `low` / `med` / `high` |
| **5h** | 5 小时速率限制用量百分比 + 重置时间 | `5h 83% 2:00` |
| **7d** | 7 天速率限制用量百分比 + 重置时间 | `7d 63% 03 06 08:00` |
| **extra** | 额外用量积分（启用时才显示） | `extra $12.34/$20.00` |

用量百分比按阈值变色：🟢 <50% → 🟡 ≥50% → 🟠 ≥70% → 🔴 ≥90%

`bars` 布局现支持和 Codex 类似的多行结构：

- 第 1 行：`repo@branch`
- 第 2 行：`model | eff | ctx`
- 第 3 / 4 行：`5h` 与 `7d` 进度条
- 可通过配置关闭前两行，最少保留两条用量 bar

---

## 配置

Claude 推荐使用共享键名 `STATUSLINE_*`；旧 `CLAUDE_CODE_STATUSLINE_*` 仍兼容。

配置优先级：

1. 进程环境变量
2. `~/.claude/settings.json` 的 `env` 字段
3. 脚本默认值

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `STATUSLINE_MODE` | `compact` | 布局模式：`compact` 或 `bars` |
| `STATUSLINE_BAR_STYLE` | `ascii` | 进度条字符（见 [README 进度条样式](../README.md#-布局与样式)），支持 `custom:X:Y` 自定义 |
| `STATUSLINE_THEME` | `default` | 配色主题：`default`、`forest`、`dracula`、`monokai`、`solarized`、`ocean`、`sunset`、`amber`、`rose` |
| `STATUSLINE_SHOW_GIT_LINE` | `true` | `bars` 布局下是否显示第 1 行 `repo@branch` |
| `STATUSLINE_SHOW_OVERVIEW_LINE` | `true` | `bars` 布局下是否显示第 2 行 `model \| eff \| ctx` |
| `STATUSLINE_SHOW_HOURLY_BAR` | `true` | `bars` 布局下是否显示第 3 行 `5h` bar |
| `STATUSLINE_SHOW_DAILY_BAR` | `true` | `bars` 布局下是否显示第 4 行 `7d` bar |
| `STATUSLINE_MAX_WIDTH` | 终端宽度 | 强制指定宽度预算（正整数） |
| `STATUSLINE_DAILY_TIME_FORMAT` | `%m %d %H:%M` | 自定义 7d 重置时间格式 |

> 兼容说明：旧键名 `CLAUDE_CODE_STATUSLINE_LAYOUT`、`CLAUDE_CODE_STATUSLINE_SHOW_GIT_LINE` 等仍可继续使用；同一层级下如果共享键名与旧键名同时存在，共享键名优先。

### 7d 时间格式支持的 strftime 标记

| 标记 | 含义 | 示例 |
|------|------|------|
| `%y` | 两位年份 | `26` |
| `%Y` | 四位年份 | `2026` |
| `%m` | 月（补零） | `03` |
| `%d` | 日（补零） | `06` |
| `%H` | 时（24h，补零） | `08` |
| `%M` | 分（补零） | `00` |
| `%b` | 缩写月名 | `Mar` |
| `%B` | 完整月名 | `March` |

无效格式自动回退到 `%m %d %H:%M`。

### 持久化配置示例

在 `~/.claude/settings.json` 的 `env` 字段中添加：

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  },
  "env": {
    "STATUSLINE_MODE": "bars",
    "STATUSLINE_SHOW_GIT_LINE": "true",
    "STATUSLINE_SHOW_OVERVIEW_LINE": "true",
    "STATUSLINE_SHOW_HOURLY_BAR": "true",
    "STATUSLINE_SHOW_DAILY_BAR": "true",
    "STATUSLINE_BAR_STYLE": "dots",
    "STATUSLINE_THEME": "forest",
    "STATUSLINE_DAILY_TIME_FORMAT": "%b %d %H:%M"
  }
}
```

### 切换示例

默认 4 行：

```text
repo@branch
Opus 4.6 | eff low | ctx 15k/200k 7%
5h 83% [========--] 2:00
7d 63% [======----] 03 06 08:00
```

关闭 git 行和 7d bar：

```json
{
  "env": {
    "STATUSLINE_MODE": "bars",
    "STATUSLINE_SHOW_GIT_LINE": "false",
    "STATUSLINE_SHOW_DAILY_BAR": "false"
  }
}
```

输出会变成：

```text
Opus 4.6 | eff low | ctx 15k/200k 7%
5h 83% [========--] 2:00
```

---

## 宽度自适应

状态栏会根据终端宽度自动裁剪，按以下优先级逐步缩减：

| 优先级 | 操作 |
|--------|------|
| 1 | 移除 `extra` 段落 |
| 2 | 隐藏 7d 重置时间 |
| 3 | 隐藏 5h 重置时间 |
| 4 | 隐藏 Git diff 统计 |
| 5 | 移除整个 7d 段落 |
| 6 | 用 `...` 截断 Git 段落 |

在 `bars` 布局中，裁剪顺序与 Codex 接近：

| 优先级 | 操作 |
|--------|------|
| 1 | `repo@branch` 单独按宽度截断分支名 |
| 2 | `5h` 行优先隐藏 reset 时间 |
| 3 | `7d` 行优先降级到短日期 |
| 4 | bar 会优先保留最小可读宽度；如果终端太窄，对应 `5h` / `7d` 行会自动隐藏 |

---

## 缓存

| 平台 | 缓存路径 | TTL |
|------|----------|-----|
| macOS / Linux | `/tmp/claude/statusline-usage-cache.json` | 60 秒 |
| Windows | `%TEMP%\claude\statusline-usage-cache.json` | 60 秒 |

---

## 冒烟测试

```bash
# Bash
printf '%s' '{"cwd":"/tmp","model":{"display_name":"Opus 4.6"}}' | ./statusline.sh

# bars 模式
STATUSLINE_MODE=bars \
printf '%s' '{"cwd":"/tmp","model":{"display_name":"Opus 4.6"}}' | ./statusline.sh

# 只看 5h bar
STATUSLINE_MODE=bars \
STATUSLINE_SHOW_DAILY_BAR=false \
printf '%s' '{"cwd":"/tmp","model":{"display_name":"Opus 4.6"}}' | ./statusline.sh

# PowerShell
pwsh -NoProfile -File ./statusline.ps1 < sample.json
```

---

## 常见问题

<details>
<summary><strong>状态栏显示 <code>5h -</code> / <code>7d -</code>，没有用量数据？</strong></summary>

确认你的 Claude Code 使用的是 OAuth 认证（Pro/Max 订阅）。API key 模式不支持用量查询。如果认证正常，可能是 API 暂时不可达，60 秒后会重新尝试。
</details>

<details>
<summary><strong>reset 时间没有显示？</strong></summary>

如果 API 返回的重置时间已过期（早于当前时间），状态栏会自动隐藏该时间，只保留百分比显示。这是预期行为。
</details>

<details>
<summary><strong>Windows 下进度条乱码？</strong></summary>

PowerShell 脚本使用代码点构建 Unicode 字符，不依赖源文件编码。如果仍有问题，使用默认的 `ascii` 风格（`=` / `-`）即可正常显示。
</details>
