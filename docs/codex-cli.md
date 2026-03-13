# Codex CLI 状态栏 — 安装与配置

Codex CLI 没有像 Claude Code 那样的原生 `statusLine.command` 扩展点，本项目通过 `tmux` 包装层实现功能丰富的底部状态栏。

---

## 数据来源

Codex session JSONL 文件（`~/.codex/sessions/`）中的 `token_count` 事件提供：

- 累计 token 用量（input / cached / output / reasoning / total）
- Context window 大小（如 258400）
- 5h 速率限制（`rate_limits.primary`）— 已用百分比 + Unix 时间戳重置时间
- weekly 速率限制（`rate_limits.secondary`）— 已用百分比 + Unix 时间戳重置时间，用于格式化绝对重置时间

模型名和推理努力等级从 `~/.codex/config.toml` 读取。

> **注意：** Codex 不提供 extra usage 数据，因此不显示 `extra` 段落。

---

## 前置依赖

| 工具 | 用途 |
|------|------|
| `tmux` | 终端复用器，承载底部状态栏 |
| `jq` | 解析 session JSONL |
| Codex CLI | OpenAI 的 CLI 编码助手 |

---

## 安装

### 方式一：一键安装脚本（推荐）

```bash
git clone https://github.com/kaelinda/AICodingStatusLine.git
cd AICodingStatusLine
./install.sh --target codex
```

这会安装 3 个文件到 `~/.codex/bin/`：

| 文件 | 说明 |
|------|------|
| `codex-tmux` | tmux 启动器，创建会话并配置状态栏 |
| `codex-statusline` | 状态栏渲染脚本（从 session JSONL 读取数据） |
| `codex-tmux-status` | 兼容层（重定向到 codex-statusline） |

可追加选项：

```bash
# 同时安装 Claude Code 和 Codex
./install.sh --target both

# 指定主题、布局和进度条样式
./install.sh --target codex --theme dracula --layout bars --bar-style blocks

# 卸载
./install.sh --uninstall
```

### 方式二：手动安装

```bash
mkdir -p ~/.codex/bin

cp codex_tmux.sh ~/.codex/bin/codex-tmux
cp codex_statusline.sh ~/.codex/bin/codex-statusline
chmod +x ~/.codex/bin/codex-tmux ~/.codex/bin/codex-statusline
```

建议将 `~/.codex/bin` 加入 `PATH`：

```bash
echo 'export PATH="$HOME/.codex/bin:$PATH"' >> ~/.zshrc  # 或 ~/.bashrc
source ~/.zshrc
```

---

## 使用

```bash
# 完整路径
~/.codex/bin/codex-tmux

# 如果已在 PATH 中
codex-tmux

# 带环境变量启动
CODEX_MODEL_NAME=o3 CODEX_STATUSLINE_THEME=dracula codex-tmux
```

启动后会创建一个以项目目录命名的 tmux 会话（如 `codex-myproject`），底部显示状态栏。

---

## 显示段落

| 段落 | 含义 | 示例 |
|------|------|------|
| **Model** | 当前模型名称 | `gpt-5.4` |
| **CWD@Branch** | 当前目录名 + Git 分支，仓库有改动时追加 `(+N -N)` | `myapp@main (+3 -1)` |
| **ctx** | 已用 / 总计 Context Window Token 数 + 百分比 | `ctx 89k/258k 34%` |
| **eff** | 推理努力等级 | `low` / `med` / `high` |
| **5h** | 5 小时速率限制剩余百分比 + 重置时间 | `5h 86% left 13:30` |
| **weekly** | 长周期速率限制剩余百分比 + 绝对重置时间 | `weekly 96% left 3/25 0:00 reset` |

剩余额度按阈值变色：🟢 >50% → 🟡 ≤50% → 🟠 ≤30% → 🔴 ≤10%

---

## 配置

Codex 支持两种配置方式，**环境变量优先级高于 config.toml**。

### 环境变量

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `CODEX_STATUSLINE_THEME` | `default` | 主题（与 Claude Code 相同的 9 种） |
| `CODEX_STATUSLINE_LAYOUT` | `compact` | 布局：`compact` 或 `bars` |
| `CODEX_STATUSLINE_BAR_STYLE` | `ascii` | 进度条样式（见 [README 进度条样式](../README.md#-布局与样式)），支持 `custom:填充:空白` 自定义 |
| `CODEX_STATUSLINE_MAX_WIDTH` | 终端宽度 | 强制指定宽度预算 |
| `CODEX_STATUSLINE_SESSION_DIR` | `~/.codex/sessions` | 会话目录覆盖 |
| `CODEX_STATUSLINE_TWO_WEEK_TIME_FORMAT` | `%-m/%-d %-H:%M reset` | `weekly` 时间格式，支持 `%y %Y %m %d %H %M %b %B` 与空格、`/`、`:`、`-` |
| `CODEX_MODEL_NAME` | 从 config.toml | 覆盖模型名 |
| `CODEX_EFFORT_LEVEL` | 从 config.toml | 覆盖推理努力等级 |

### config.toml 配置（推荐持久化方式）

在 `~/.codex/config.toml` 中添加 `[statusline]` 段落：

```toml
[statusline]
theme = "dracula"
layout = "bars"
bar_style = "blocks"
two_week_time_format = "%y-%m-%d %H:%M"
```

支持的键：

| 键 | 可选值 | 说明 |
|----|--------|------|
| `theme` | `default`、`forest`、`dracula`、`monokai`、`solarized`、`ocean`、`sunset`、`amber`、`rose` | 配色主题 |
| `layout` | `compact`、`bars` | 布局模式 |
| `bar_style` | `ascii`、`dots`、`squares`、`blocks`、`braille`、`shades`、`diamonds`、`custom:X:Y` | 进度条样式 |
| `two_week_time_format` | 合法 `strftime` 子集 | `weekly` 绝对时间格式 |

**完整 config.toml 示例：**

```toml
model = "gpt-5.4"
model_reasoning_effort = "high"

[statusline]
theme = "ocean"
layout = "bars"
bar_style = "diamonds"
two_week_time_format = "%m/%d %H:%M"
```

---

## 宽度自适应

状态栏会根据终端宽度自动裁剪，按以下优先级逐步缩减：

| 优先级 | 操作 |
|--------|------|
| 1 | 隐藏 weekly 完整时间，降级为短日期 |
| 2 | 隐藏 5h 重置时间 |
| 3 | 隐藏 Git diff 统计 |
| 4 | 移除整个 weekly 段落 |
| 5 | 用 `...` 截断 Git 段落 |

在 `bars` 布局中，概览行先裁剪；5h / weekly 进度条行会先缩短时间文本，最后才缩小进度条宽度。

---

## 缓存

| 缓存路径 | TTL | 说明 |
|----------|-----|------|
| `/tmp/codex/statusline-session-cache.json` | 10 秒 | 从 session JSONL 解析的 token/rate_limits 数据 |

可通过 `CODEX_STATUSLINE_CACHE_FILE` 环境变量覆盖缓存路径。

---

## tmux 多行布局（bars）

`bars` 布局在 tmux 中显示为 4 行：

```
第 1 行：myapp@main
第 2 行：gpt-5.4 | eff high | ctx 89k/258k 34%
第 3 行：5h 86% left [████████░░░░░░░░░░░░] 13:30 reset
第 4 行：weekly 96% left [█░░░░░░░░░░░░░░░░░░░] 3/25 0:00 reset
```

`codex_tmux.sh` 会自动检测 `bars` 布局并配置 tmux 四行状态栏（`status 4`），无需手动设置。

布局来源优先级：环境变量 `CODEX_STATUSLINE_LAYOUT` > `config.toml` 的 `[statusline].layout` > 默认 `compact`。

---

## 冒烟测试

```bash
# 基本测试
CODEX_MODEL_NAME=gpt-5.4 ./codex_statusline.sh .

# 指定宽度
CODEX_STATUSLINE_MAX_WIDTH=80 ./codex_statusline.sh .

# 指定主题
CODEX_STATUSLINE_THEME=dracula ./codex_statusline.sh .

# bars 布局
CODEX_STATUSLINE_LAYOUT=bars ./codex_statusline.sh .
```

---

## 常见问题

<details>
<summary><strong>状态栏显示 <code>5h -</code> / <code>weekly -</code>，或 bars 布局显示 <code>unavailable</code>？</strong></summary>

说明当前拿不到可用的 rate-limit 数据。常见原因有两种：

- 找不到有效的 session JSONL 文件，或文件中没有 `token_count` 事件。
- session 中虽然有 `token_count`，但 `payload.rate_limits` 为 `null`。这在较新的 Codex CLI 中可能出现。

确认 Codex CLI 已运行过至少一次对话，并检查 `~/.codex/sessions/` 目录下最新 `.jsonl` 是否包含 `token_count`。如果 `rate_limits` 缺失，状态栏会保留 `ctx` 等本地可得信息，并把 `5h` / `weekly` 明确标记为 `unavailable`。
</details>

<details>
<summary><strong>tmux 状态栏显示乱码？</strong></summary>

状态栏会自动检测 tmux 环境并使用 `#[fg=...]` 格式。如果仍有问题，检查终端是否支持 256 色或 true color：`echo $TERM` 应为 `xterm-256color` 或 `tmux-256color`。
</details>

<details>
<summary><strong>bars 布局只显示一行？</strong></summary>

确认你使用的是 `codex-tmux` 启动器，它会自动配置 tmux 多行状态栏。如果直接在已有 tmux 会话中使用，需要手动设置 `tmux set status 4`。
</details>

<details>
<summary><strong>如何切换进度条样式？</strong></summary>

在 `~/.codex/config.toml` 中修改：

```toml
[statusline]
bar_style = "diamonds"
```

或使用自定义字符：

```toml
[statusline]
bar_style = "custom:▰:▱"
```

修改后重新进入 tmux 会话即可生效。
</details>

<details>
<summary><strong>如何完全不显示 bars 进度条？</strong></summary>

将布局设为 `compact`（默认值），所有信息会压缩在一行内显示。
</details>
