<p align="center">
  <img src="screenshot.png" alt="终端状态栏示例，显示模型、目录与分支、ctx、5h、7d 和 extra 用量" width="100%">
</p>

<h1 align="center">AICodingStatusLine</h1>

<p align="center">
  <strong>Claude Code 状态栏 + Codex CLI 状态栏</strong><br>
  Claude 走原生 statusLine hook，Codex 支持原生 <code>tui.status_line</code>，本项目额外提供 tmux 增强底栏
</p>

<p align="center">
  <a href="https://github.com/kaelinda/AICodingStatusLine/releases"><img src="https://img.shields.io/github/v/release/kaelinda/AICodingStatusLine?style=flat-square" alt="Release"></a>
  <a href="#-license"><img src="https://img.shields.io/github/license/kaelinda/AICodingStatusLine?style=flat-square" alt="License"></a>
</p>

<p align="center">
  <a href="#-快速安装">安装</a>&nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="#-claude-code">Claude Code</a>&nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="#-codex-cli">Codex CLI</a>&nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="#-statusline-skill">Skill</a>&nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="#-主题">主题</a>&nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="#-布局与样式">布局</a>&nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="#-常见问题">FAQ</a>
</p>

---

## 🚀 快速安装

### 方式一：Claude Code Plugin（推荐）

```bash
# 1. 添加 Marketplace
claude plugin marketplace add https://github.com/kaelinda/AICodingStatusLine.git

# 2. 安装插件
claude plugin install aicoding-statusline
```

安装后每次启动 Claude Code 会自动检查并配置状态栏（幂等，仅首次或脚本更新时执行）。

### 方式二：手动安装

```bash
git clone https://github.com/kaelinda/AICodingStatusLine.git
cd AICodingStatusLine
./install.sh                       # Claude Code（默认）
./install.sh --target codex        # Codex tmux 增强模式
./install.sh --target codex-native # Codex 原生 tui.status_line
./install.sh --target codex --with-hooks # Codex tmux + 实验性 hooks sidecar
./install.sh --target codex-native --with-notify # Codex 原生状态栏 + notify bridge
./install.sh --target codex --with-hooks --with-notify # Codex tmux + hooks + notify
./install.sh --target both         # Claude + Codex tmux
```

支持安装时指定配置：

```bash
./install.sh --target both --theme dracula --layout bars --bar-style dots
```

卸载：

```bash
./install.sh --uninstall
```

更新：

```bash
git pull --ff-only

# 按你当前使用的模式重新执行一次安装命令
./install.sh --target codex-native
./install.sh --target codex
./install.sh --target codex --with-hooks
./install.sh --target codex --with-hooks --with-notify
```

---

## 🔵 Claude Code

通过原生 `statusLine.command` hook 驱动，从 stdin 接收 JSON，调用 Anthropic API 获取用量信息。

**显示内容：** 模型名 | 推理努力 | Git 分支(+N -N ?N，分别表示新增/删除/未跟踪文件数) | ctx 使用率（context window） | 5h 限制 | 7d 限制 | extra 用量

**配置方式：** 在 Claude Code 对话中输入 `/statusline` 交互式管理，或手动编辑 `~/.claude/settings.json` 的 `env` 字段。

> 详细安装步骤、完整配置参考、手动安装（含 Windows）请看 → [docs/claude-code.md](docs/claude-code.md)

---

## 🟢 Codex CLI

截至 2026-04-02，Codex 已经提供原生 `tui.status_line`，可配置基础状态栏项；另外还有实验性 hooks 能力。本项目当前为 Codex 提供两种接入方式：

- **原生模式**：写入 `~/.codex/config.toml` 的 `tui.status_line`，使用 Codex 官方 TUI 状态栏
- **tmux 增强模式**：通过 `codex-tmux` 包装层补充 `5h` / `weekly`、多行 bars、Git diff、主题和宽度裁剪等增强能力

如果你只想要官方内建 footer，用原生模式；如果你要多行进度条和速率限制展示，用 tmux 增强模式。

### 原生模式

安装：

```bash
./install.sh --target codex-native
```

这会把以下配置写入 `~/.codex/config.toml`：

```toml
[tui]
status_line = ["model-with-reasoning", "context-remaining", "current-dir"]
```

更新原生模式：

```bash
git pull --ff-only
./install.sh --target codex-native
```

### tmux 增强模式

本项目的增强模式通过 `tmux` 包装层实现底部状态栏，并从 session JSONL 读取 token 用量和 `5h` / `weekly` 剩余额度。

启动：

```bash
codex-tmux               # 需要 ~/.codex/bin 在 PATH 中
~/.codex/bin/codex-tmux   # 或使用完整路径
```

更新 tmux 增强模式：

```bash
git pull --ff-only
./install.sh --target codex
./install.sh --target codex --with-hooks
./install.sh --target codex --with-hooks --with-notify
```

显示内容：

- `compact`：模型名 | 推理努力 | ctx 使用率 | git 分支(+N -N ?N) | 5h 剩余额度 | weekly 剩余额度（长周期额度）
- `bars`：第 1 行 `repo@branch`，第 2 行 `model | eff | ctx`，第 3 / 4 行为 `5h` 和 `weekly` 进度条

其中 `ctx` 是 context window 使用率，`weekly` 是长周期额度摘要；在窄宽度下会优先保留百分比，再按空间裁剪时间文本。

配置方式：通过 `~/.codex/config.toml` 的 `[statusline]` 段落持久化配置。

```toml
[statusline]
theme = "dracula"
layout = "bars"
bar_style = "blocks"
show_git_line = true
show_overview_line = true
```

> 详细安装步骤、完整配置参考、tmux 多行布局说明请看 → [docs/codex-cli.md](docs/codex-cli.md)

### 实验性 hooks

Codex 现在还有实验性 hooks。它们更适合做生命周期脚本、通知、sidecar 状态采集，不是 Claude 那种可直接自定义整条状态栏渲染的 `statusLine.command`。

启用方式示例：

```toml
[features]
codex_hooks = true
```

本项目现在支持通过安装脚本一键接入 hooks sidecar：

```bash
./install.sh --target codex --with-hooks
```

这会自动：

- 安装 `~/.codex/bin/codex-hook-sidecar`
- 生成或合并 `~/.codex/hooks.json`
- 打开 `~/.codex/config.toml` 中的 `[features].codex_hooks = true`
- 在 tmux 增强模式下自动开启 `show_hook_segment = true`

接入后，增强状态栏会多一个 `hook` 段落，用来显示最近一次 hooks 状态，例如：

- `hook bash run`
- `hook bash ok`
- `hook bash fail`
- `hook startup`

> 官方当前仍有限制：`PreToolUse` / `PostToolUse` 的 matcher 目前只会收到 `Bash`，所以本项目的 sidecar 也只针对 Bash 工具流提供实时状态。

### 原生通知 / notify bridge

Codex 还支持顶层 `notify` 命令，用于在需要你关注时把 JSON payload 交给外部命令。本项目把它封装成一个轻量 bridge，可以和原生模式或 tmux 增强模式叠加使用。

安装示例：

```bash
./install.sh --target codex-native --with-notify
./install.sh --target codex --with-hooks --with-notify
```

这会自动：

- 安装 `~/.codex/bin/codex-notify-bridge`
- 写入 `~/.codex/config.toml` 顶层 `notify = ["~/.codex/bin/codex-notify-bridge"]`
- 打开 `[tui].notifications = true`

bridge 当前会：

- 接收 Codex 发出的通知 payload，并把最近一次通知写到 `/tmp/codex/statusline-notify-cache.json`
- 在支持的平台上尝试转发桌面通知：macOS 使用 `osascript`，Linux 使用 `notify-send`
- 不要求 tmux；因此适合原生 `tui.status_line` 用户
- 如果你在 tmux 增强模式下安装了 `--with-notify`，状态栏会自动显示 `notify ...` 段落

---

## 🛠 /statusline Skill

在 Claude Code 对话中直接管理状态栏配置，无需手动编辑 JSON。

**命令：**

| 命令 | 说明 |
|------|------|
| `/statusline` | 展示当前配置 + 可用命令 |
| `/statusline show` | 仅展示当前配置表格 |
| `/statusline segments` | 交互式多选段落可见性（`[x]/[ ]` checkbox） |
| `/statusline segments show <name>` | 显示指定段落 |
| `/statusline segments hide <name>` | 隐藏指定段落 |
| `/statusline segments reset` | 重置段落（显示全部） |
| `/statusline theme [值]` | 单选主题（`(●)/( )` radio，9 种，支持模糊匹配） |
| `/statusline layout [值]` | 单选布局（`bars` / `compact`） |
| `/statusline bar-style [值]` | 单选进度条样式（7 种 + 自定义） |
| `/statusline pct-mode [值]` | 单选百分比模式（`used` / `left`） |
| `/statusline max-width [值\|auto]` | 设置宽度预算 |
| `/statusline time-format [值]` | 设置 7d 时间格式（strftime） |
| `/statusline reset` | 恢复所有配置为默认值 |
| `/statusline preview [主题]` | ANSI 色块预览主题色板 |
| `/statusline update` | 从 GitHub 拉取最新版本并安装 |

**特性：**

- 交互式选择：段落 checkbox 多选、主题/布局 radio 单选，类似 Codex CLI 风格
- 模糊匹配：`drac` → `dracula`、`sol` → `solarized`
- 智能联动：改 `bar-style` 时提醒切换到 `bars` 布局；选 `bars` 布局时推荐非 ascii 样式
- 变更前后对比：每次修改显示旧值 → 新值
- 主题预览：输出 ANSI 色块展示 9 个颜色角色
- 组合推荐：说"推荐暗色主题"可获得主题 + 布局 + 样式的预设方案
- 一键更新：`/statusline update` 从 GitHub 拉取最新版本并安装到本地

> `/statusline` 仅适用于 Claude Code。Codex CLI 的配置请直接编辑 `~/.codex/config.toml`。

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

**冷色系：**

| 色彩角色 | `default` | `forest` | `dracula` | `monokai` | `solarized` | `ocean` |
|----------|-----------|----------|-----------|-----------|-------------|---------|
| 主强调色 | 🔵 `#4DA6FF` | 🟢 `#78C478` | 🟣 `#BD93F9` | 🔵 `#66D9EF` | 🔵 `#268BD2` | 🔵 `#00BCD4` |
| 目录/Teal | `#4DAFB0` | `#5EAA96` | `#8BE9FD` | `#A6E22E` | `#2AA198` | `#0097A7` |
| 分支名 | `#C4D0D4` | `#D6E0CD` | `#F8F8F2` | `#E6DB74` | `#93A1A1` | `#B2EBF2` |
| 弱化文字 | `#73848B` | `#84907C` | `#6272A4` | `#75715E` | `#586E75` | `#78909C` |

**暖色系：**

| 色彩角色 | `sunset` | `amber` | `rose` |
|----------|----------|---------|--------|
| 主强调色 | 🟠 `#FF8A65` | 🟡 `#FFC107` | 🩷 `#F48FB1` |
| 目录/Teal | `#FFB74D` | `#DCB86A` | `#CE93D8` |
| 分支名 | `#FFCC80` | `#F0E6C8` | `#F8D7E0` |
| 弱化文字 | `#A1887F` | `#9E9477` | `#AD8B9F` |

---

## 🎨 布局与样式

### 布局模式

| 值 | 说明 | Claude Code 环境变量 | Codex 环境变量 / config.toml |
|----|------|---------------------|------------------------------|
| `bars` | **默认**。Claude 为 3 行；Codex 为 2–4 行（含进度条） | `CLAUDE_CODE_STATUSLINE_LAYOUT` | `CODEX_STATUSLINE_LAYOUT` / `layout` |
| `compact` | 所有信息压缩在一行 | 同上 | 同上 |

### 进度条样式（仅 `bars` 布局生效）

| 值 | 填充 / 空白 | 效果 |
|----|-------------|------|
| `ascii` | `=` / `-` | `[===-------]` **默认** |
| `dots` | `●` / `○` | `[●●●○○○○○○○]` |
| `squares` | `■` / `□` | `[■■■□□□□□□□]` |
| `blocks` | `█` / `░` | `[███░░░░░░░]` |
| `braille` | `⣿` / `⣀` | `[⣿⣿⣿⣀⣀⣀⣀⣀⣀⣀]` |
| `shades` | `▓` / `░` | `[▓▓▓░░░░░░░]` |
| `diamonds` | `◆` / `◇` | `[◆◆◆◇◇◇◇◇◇◇]` |
| `custom:X:Y` | 自定义 | 如 `custom:▰:▱` |

未知值自动回退到 `ascii`。

### 百分比模式

| 值 | 显示效果 | Claude Code 环境变量 | Codex 环境变量 |
|----|---------|---------------------|----------------|
| `used` | **默认**。`5h 8%` / `7d 19%`（已用百分比） | `CLAUDE_CODE_STATUSLINE_PCT_MODE` | `CODEX_STATUSLINE_PCT_MODE` |
| `left` | `5h 92% left` / `7d 81% left`（剩余百分比） | 同上 | 同上 |

`left` 模式下进度条填充方向同步反转（剩余多则填充多），颜色始终基于使用量判断（使用少=绿色，使用多=红色）。

### Codex bars 行显示开关

仅 Codex 的 `bars` 布局支持控制前两行是否显示：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `CODEX_STATUSLINE_SHOW_GIT_LINE` / `show_git_line` | `true` | 第 1 行 `repo@branch` |
| `CODEX_STATUSLINE_SHOW_OVERVIEW_LINE` / `show_overview_line` | `true` | 第 2 行 `model \| eff \| ctx` |

### 截图对比

**`dots` 风格：**

![Bars Dots Screenshot](screenshot-dots.png)

**`squares` 风格：**

![Bars Squares Screenshot](screenshot-squares.png)

---

## 📐 宽度自适应

状态栏会根据终端宽度自动裁剪：

**Claude Code 裁剪优先级：**

| 优先级 | 操作 |
|--------|------|
| 1 | 移除 `extra` 段落 |
| 2 | 隐藏 7d 重置时间 |
| 3 | 隐藏 5h 重置时间 |
| 4 | 隐藏 Git diff 统计 |
| 5 | 移除整个 7d 段落 |
| 6 | 用 `...` 截断 Git 段落 |

**Codex CLI（compact）裁剪优先级：**

| 优先级 | 操作 |
|--------|------|
| 1 | weekly 时间降级为短日期 |
| 2 | 隐藏 5h 重置时间 |
| 3 | 隐藏 Git diff 统计 |
| 4 | 移除整个 weekly 段落 |
| 5 | 用 `...` 截断 Git 段落 |

---

## 📁 项目结构

```
├── .claude-plugin/
│   ├── plugin.json          # Claude Code Plugin 清单
│   └── marketplace.json     # Marketplace 注册清单
├── scripts/
│   ├── statusline.sh        # Claude Code 状态栏（Bash）
│   ├── statusline.ps1       # Claude Code 状态栏（PowerShell）
│   ├── codex_statusline.sh  # Codex CLI 状态栏
│   ├── codex_tmux.sh        # Codex tmux 启动器
│   ├── codex_tmux_status.sh # Codex tmux 状态栏渲染
│   ├── codex_hook_sidecar.sh # Codex hooks sidecar 缓存写入器
│   ├── codex_notify_bridge.sh # Codex notify bridge
│   ├── codex_statusline_common.sh  # Codex 公共函数库
│   └── post-install.sh      # SessionStart hook（幂等安装脚本）
├── skills/
│   └── statusline/          # /statusline Skill
├── install.sh               # 手动一键安装脚本
└── tests/
    └── test_statusline.py   # 测试套件（103 项）
```

---

## 🧪 测试

```bash
python3 tests/test_statusline.py                                     # 完整测试套件
printf '%s' '{"cwd":"/tmp","model":{"display_name":"Opus 4.6"}}' | ./scripts/statusline.sh  # Claude Code 冒烟测试
CODEX_MODEL_NAME=gpt-5.4 ./scripts/codex_statusline.sh .            # Codex 冒烟测试
```

---

## ❓ 常见问题

<details>
<summary><strong>只显示 <code>5h -</code> / <code>7d -</code>（或 <code>weekly -</code>）是什么意思？</strong></summary>

这表示当前没有拿到可用的额度数据，不是“额度为 0”。

- **Claude Code**：确认使用 OAuth 认证（Pro/Max 订阅）。API key 模式不支持用量查询；如果认证正常但接口暂时不可达，脚本会在 60 秒内自动重试。
- **Codex CLI**：确认 `~/.codex/sessions/` 下已经生成最新 `.jsonl`，并且至少跑过一次带 `token_count` 的对话。
</details>

<details>
<summary><strong>为什么没有显示重置时间？</strong></summary>

只有“未来的重置时间”才会显示。如果接口没返回时间，或者返回的时间已经早于当前时间，状态栏会自动只保留百分比。这是预期行为。
</details>

<details>
<summary><strong>终端宽度不够，段落被截断了？</strong></summary>

这是宽度自适应功能的正常表现。可以加宽终端窗口，或通过 `MAX_WIDTH` 环境变量手动指定更大的宽度预算。
</details>

<details>
<summary><strong>Windows 下进度条乱码？</strong></summary>

PowerShell 脚本使用代码点构建 Unicode 字符，不依赖源文件编码。如果仍有问题，使用默认的 `ascii` 风格即可。
</details>

<details>
<summary><strong>如何隐藏 Codex bars 的前两行？</strong></summary>

```toml
[statusline]
layout = "bars"
show_git_line = false
show_overview_line = true
```

隐藏后 tmux 状态栏会自动从 4 行缩减为 3 行或 2 行。
</details>

---

## 📄 License

MIT

## 致谢

本项目 fork 自 [daniel3303/ClaudeCodeStatusLine](https://github.com/daniel3303/ClaudeCodeStatusLine)（原作者 Daniel Oliveira），在保留原始状态栏概念和跨平台脚本的基础上扩展了主题系统、多布局、进度条样式、Codex CLI 支持和 `/statusline` Skill。

**Fork 维护：** [kaelinda/AICodingStatusLine](https://github.com/kaelinda/AICodingStatusLine)
