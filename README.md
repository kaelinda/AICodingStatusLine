<p align="center">
  <img src="screenshot.png" alt="AICodingStatusLine" width="100%">
</p>

<h1 align="center">AICodingStatusLine</h1>

<p align="center">
  <strong>Claude Code 状态栏 + Codex CLI 状态栏</strong> — Claude 走原生 statusLine hook，Codex 走 tmux 底栏
</p>

<p align="center">
  <a href="#-claude-code">Claude Code</a>&nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="#-codex-cli">Codex CLI</a>&nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="#-布局与样式">布局</a>&nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="#-主题">主题</a>&nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="#-常见问题">FAQ</a>
</p>

---

## Fork 说明

本仓库 fork 自 [daniel3303/ClaudeCodeStatusLine](https://github.com/daniel3303/ClaudeCodeStatusLine)（原作者 Daniel Oliveira），在保留原始状态栏概念和跨平台脚本的基础上增加了以下特性：

- 自适应宽度裁剪
- 9 种主题配色预设（含冷色系与暖色系）
- 多行 `bars` 布局 + 7 种内置进度条样式 + 自定义字符支持
- 自定义重置时间格式
- 过期 reset 时间自动隐藏
- PowerShell 安全的 Unicode 渲染
- Codex CLI 完整状态栏（tmux 底栏，从 session JSONL 读取 token + rate limits）

---

## 🔵 Claude Code

通过原生 `statusLine.command` hook 驱动，从 stdin 接收 JSON，调用 Anthropic API 获取用量信息。

**快速安装：**

```bash
git clone https://github.com/kaelinda/AICodingStatusLine.git
cd AICodingStatusLine
./install.sh
```

**显示内容：** 模型名 | Git 分支(+N -N) | ctx 使用率 | 推理努力 | 5h 限制 | 7d 限制 | extra 用量

**配置方式：** 通过 `~/.claude/settings.json` 的 `env` 字段设置环境变量。

> **详细安装步骤、完整配置参考、手动安装（含 Windows）请看 → [docs/claude-code.md](docs/claude-code.md)**

---

## 🟢 Codex CLI

Codex CLI 没有原生 statusLine 扩展点，本项目通过 `tmux` 包装层实现功能丰富的底部状态栏。从 session JSONL 读取 token 用量和 5h / weekly 剩余额度。

**快速安装：**

```bash
git clone https://github.com/kaelinda/AICodingStatusLine.git
cd AICodingStatusLine
./install.sh --target codex
```

安装后会在 `~/.codex/bin/` 下生成 `codex-tmux`（启动器）和 `codex-statusline`（渲染脚本）；bars 布局下会自动配置 tmux 多行状态栏。

**启动：**

```bash
codex-tmux               # 需要 ~/.codex/bin 在 PATH 中
~/.codex/bin/codex-tmux   # 或使用完整路径
```

**显示内容：**

- `compact`：模型名 | 推理努力 | ctx 使用率 | `git 分支(+N -N)` | 5h 剩余额度 | weekly 剩余额度
- `bars`：第 1 行 `repo@branch`，第 2 行 `model | eff | ctx`，第 3 / 4 行为 `5h` 和 `weekly` 进度条

**配置方式：** 通过 `~/.codex/config.toml` 的 `[statusline]` 段落持久化配置。

> Codex 中 `5h` 和 `weekly` 都显示剩余额度；`weekly` 会带绝对重置时间，默认例如 `weekly 96% left 3/25 0:00 reset`，并继续支持自定义时间格式。

**示例输出：**

```text
gpt-5.4 | myapp@main | ctx 89k/258k 34% | eff high | 5h 86% left 8:00 | weekly 96% left 3/25 0:00 reset
```

```toml
[statusline]
theme = "dracula"
layout = "bars"
bar_style = "blocks"
show_git_line = true
show_overview_line = true
```

> **详细安装步骤、完整配置参考、tmux 多行布局说明请看 → [docs/codex-cli.md](docs/codex-cli.md)**

---

## 同时安装

```bash
./install.sh --target both --theme dracula --layout bars --bar-style dots
```

卸载：

```bash
./install.sh --uninstall
```

---

## 🎨 布局与样式

### 布局模式

| 值 | 说明 | Claude Code 环境变量 | Codex 环境变量 / config.toml |
|----|------|---------------------|------------------------------|
| `compact` | **默认**。所有信息压缩在一行 | `CLAUDE_CODE_STATUSLINE_LAYOUT` | `CODEX_STATUSLINE_LAYOUT` / `layout` |
| `bars` | Claude 为 3 行；Codex 为 2 到 4 行，可显示 `repo@branch`、概览行和两条进度条 | 同上 | 同上 |

### Codex bars 行显示开关

仅 Codex 的 `bars` 布局支持通过环境变量或 `~/.codex/config.toml` 控制前两行是否显示：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `CODEX_STATUSLINE_SHOW_GIT_LINE` / `show_git_line` | `true` | 控制第 1 行 `repo@branch` 是否显示 |
| `CODEX_STATUSLINE_SHOW_OVERVIEW_LINE` / `show_overview_line` | `true` | 控制第 2 行 `model \| eff \| ctx` 是否显示 |

常见组合：

```text
show_git_line=true,  show_overview_line=true   -> 4 行: git / overview / 5h / weekly
show_git_line=false, show_overview_line=true   -> 3 行: overview / 5h / weekly
show_git_line=true,  show_overview_line=false  -> 3 行: git / 5h / weekly
show_git_line=false, show_overview_line=false  -> 2 行: 5h / weekly
```

### 进度条样式（仅 `bars` 布局生效）

| 值 | 填充 / 空白 | 效果 |
|----|-------------|------|
| `ascii` | `=` / `-` | `[===-------]` **默认**，最大兼容性 |
| `dots` | `●` / `○` | `[●●●○○○○○○○]` 圆点风格 |
| `squares` | `■` / `□` | `[■■■□□□□□□□]` 方块风格 |
| `blocks` | `█` / `░` | `[███░░░░░░░]` 经典终端风格 |
| `braille` | `⣿` / `⣀` | `[⣿⣿⣿⣀⣀⣀⣀⣀⣀⣀]` 盲文点阵，极客感 |
| `shades` | `▓` / `░` | `[▓▓▓░░░░░░░]` 渐变色块 |
| `diamonds` | `◆` / `◇` | `[◆◆◆◇◇◇◇◇◇◇]` 菱形风格 |
| `custom:X:Y` | 自定义 | 任意 Unicode 字符，如 `custom:▰:▱` |

未知值自动回退到 `ascii`。

### 截图对比

**`dots` 风格：**

![Bars Dots Screenshot](screenshot-dots.png)

**`squares` 风格：**

![Bars Squares Screenshot](screenshot-squares.png)

---

## 🖌 主题

9 种主题，Claude Code 和 Codex 通用：

| 值 | 风格 | 色温 | 灵感来源 |
|----|------|------|----------|
| `default` | **默认**。蓝色主调，高对比度 | 冷色 | — |
| `forest` | 绿色主调，柔和自然 | 冷色 | — |
| `dracula` | 紫色主调，暗色背景下表现出色 | 冷色 | [Dracula Theme](https://draculatheme.com) |
| `monokai` | 青色主调，经典代码编辑器风格 | 冷色 | [Monokai Pro](https://monokai.pro) |
| `solarized` | 蓝色主调，低对比度护眼 | 冷色 | [Solarized](https://ethanschoonover.com/solarized) |
| `ocean` | 青蓝主调，清爽海洋风 | 冷色 | Material Design |
| `sunset` | 珊瑚橙主调，温暖日落氛围 | **暖色** | Material Design |
| `amber` | 琥珀金主调，沉稳大地色 | **暖色** | — |
| `rose` | 玫瑰粉主调，柔和优雅 | **暖色** | — |

未知值自动回退到 `default`。

### 配色对照

**冷色系主题：**

| 色彩角色 | `default` | `forest` | `dracula` | `monokai` | `solarized` | `ocean` |
|----------|-----------|----------|-----------|-----------|-------------|---------|
| 主强调色 | 🔵 `#4DA6FF` | 🟢 `#78C478` | 🟣 `#BD93F9` | 🔵 `#66D9EF` | 🔵 `#268BD2` | 🔵 `#00BCD4` |
| 目录/Teal | `#4DAFB0` | `#5EAA96` | `#8BE9FD` | `#A6E22E` | `#2AA198` | `#0097A7` |
| 分支名 | `#C4D0D4` | `#D6E0CD` | `#F8F8F2` | `#E6DB74` | `#93A1A1` | `#B2EBF2` |
| 弱化文字 | `#73848B` | `#84907C` | `#6272A4` | `#75715E` | `#586E75` | `#78909C` |

**暖色系主题：**

| 色彩角色 | `sunset` | `amber` | `rose` |
|----------|----------|---------|--------|
| 主强调色 | 🟠 `#FF8A65` | 🟡 `#FFC107` | 🩷 `#F48FB1` |
| 目录/Teal | `#FFB74D` | `#DCB86A` | `#CE93D8` |
| 分支名 | `#FFCC80` | `#F0E6C8` | `#F8D7E0` |
| 弱化文字 | `#A1887F` | `#9E9477` | `#AD8B9F` |

---

## 📐 宽度自适应

状态栏会根据终端宽度自动裁剪，不同客户端的优先级略有不同：

**Claude Code：**

| 优先级 | 操作 |
|--------|------|
| 1 | 移除 `extra` 段落 |
| 2 | 隐藏长周期时间信息（`7d`） |
| 3 | 隐藏 5h 重置时间 |
| 4 | 隐藏 Git diff 统计 |
| 5 | 移除整个长周期段落（`7d`） |
| 6 | 用 `...` 截断 Git 段落 |

**Codex CLI（compact）：**

| 优先级 | 操作 |
|--------|------|
| 1 | 隐藏 `weekly` 完整时间，降级为短日期 |
| 2 | 隐藏 5h 重置时间 |
| 3 | 隐藏 Git diff 统计 |
| 4 | 移除整个 `weekly` 段落 |
| 5 | 用 `...` 截断 Git 分支段落 |

**Codex CLI（bars）：**

- 第 1 行 `repo@branch` 会单独按宽度截断
- 第 2 行概览会先裁剪
- `5h` / `weekly` 行会先缩短时间文本，最后才缩小进度条宽度

---

## 🧪 测试

```bash
# 运行完整测试套件
python3 -m unittest tests/test_statusline.py

# 运行单个测试
python3 -m unittest tests.test_statusline.StatusLineTests.test_wide_budget_keeps_all_segments

# Claude Code 冒烟测试
printf '%s' '{"cwd":"/tmp","model":{"display_name":"Opus 4.6"}}' | ./statusline.sh

# Codex 冒烟测试
CODEX_MODEL_NAME=gpt-5.4 ./codex_statusline.sh .
```

---

## ❓ 常见问题

<details>
<summary><strong>状态栏显示 <code>5h -</code> / <code>7d -</code>（或 <code>weekly -</code>），bars 布局还显示 <code>unavailable</code>？</strong></summary>

- **Claude Code**：确认使用 OAuth 认证（Pro/Max 订阅），API key 模式不支持用量查询。
- **Codex CLI**：确认 `~/.codex/sessions/` 目录下有 `.jsonl` 文件，需至少运行过一次对话。较新的 session 可能只有 token 统计、没有 `rate_limits`，这时 `bars` 布局会显示 `5h unavailable` / `weekly unavailable`，表示数据源缺失，不是渲染错误。
</details>

<details>
<summary><strong>reset 时间没有显示？</strong></summary>

如果重置时间已过期（早于当前时间），状态栏会自动隐藏该时间，只保留百分比显示。这是预期行为。

Codex 的 `weekly` 段落显示为绝对重置时间；默认格式类似 `3/25 0:00 reset`，宽度不足时会自动降级为短日期 `3/25`，窗口已过期时会隐藏该时间。
</details>

<details>
<summary><strong>终端宽度不够，段落被截断了？</strong></summary>

这是宽度自适应功能的正常表现。可以加宽终端窗口，或通过对应的 `MAX_WIDTH` 环境变量手动指定更大的宽度预算。
</details>

<details>
<summary><strong>Windows 下进度条乱码？</strong></summary>

PowerShell 脚本使用代码点构建 Unicode 字符，不依赖源文件编码。如果仍有问题，使用默认的 `ascii` 风格即可正常显示。
</details>

<details>
<summary><strong>如何完全不显示 bars 进度条？</strong></summary>

将布局设为 `compact`（默认值），所有信息会压缩在一行内显示。
</details>

<details>
<summary><strong>如何隐藏 Codex bars 的前两行？</strong></summary>

在 `~/.codex/config.toml` 中配置：

```toml
[statusline]
layout = "bars"
show_git_line = false
show_overview_line = true
```

也可以临时使用环境变量：

```bash
CODEX_STATUSLINE_LAYOUT=bars \
CODEX_STATUSLINE_SHOW_GIT_LINE=false \
codex-tmux
```

隐藏后 tmux 状态栏会自动从 4 行缩减为 3 行或 2 行，不会留下空白行。
</details>

---

## 📄 License

MIT

## 作者

**原作者：** Daniel Oliveira — [daniel3303/ClaudeCodeStatusLine](https://github.com/daniel3303/ClaudeCodeStatusLine)

**本 Fork 维护于：** [kaelinda/AICodingStatusLine](https://github.com/kaelinda/AICodingStatusLine)

[![Website](https://img.shields.io/badge/Website-FF6B6B?style=for-the-badge&logo=safari&logoColor=white)](https://danielapoliveira.com/)
[![X](https://img.shields.io/badge/X-000000?style=for-the-badge&logo=x&logoColor=white)](https://x.com/daniel_not_nerd)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/daniel-ap-oliveira/)
